# --
# Kernel/System/PostMaster.pm - the global PostMaster module for OTRS
# Copyright (C) 2001-2004 Martin Edenhofer <martin+code@otrs.org>
# --
# $Id: PostMaster.pm,v 1.45 2004-10-01 08:53:32 martin Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --
package Kernel::System::PostMaster;

use strict;
use Kernel::System::DB;
use Kernel::System::EmailParser;
use Kernel::System::Ticket;
use Kernel::System::Queue;
use Kernel::System::State;
use Kernel::System::PostMaster::FollowUp;
use Kernel::System::PostMaster::NewTicket;
use Kernel::System::PostMaster::DestQueue;

use vars qw(@ISA $VERSION);

$VERSION = '$Revision: 1.45 $';
$VERSION =~ s/^\$.*:\W(.*)\W.+?$/$1/;

# --
sub new {
    my $Type = shift;
    my %Param = @_;

    # allocate new hash for object
    my $Self = {};
    bless ($Self, $Type);
    # get common opjects
    foreach (keys %Param) {
        $Self->{$_} = $Param{$_};
    }
    # check needed objects
    foreach (qw(DBObject LogObject ConfigObject Email)) {
        die "Got no $_" if (!$Param{$_});
    }
    # check needed config objects
    foreach (qw(PostmasterUserID PostmasterX-Header)) {
        $Self->{$_} = $Param{ConfigObject}->Get($_) || die "Found no '$_' option in Config.pm!";
    }

    # for debug 0=off; 1=info; 2=on; 3=with GetHeaderParam;
    $Self->{Debug} = $Param{Debug} || 0;

    # create common objects
    $Self->{TicketObject} = Kernel::System::Ticket->new(%Param);
    $Self->{ParseObject} = Kernel::System::EmailParser->new(
        Email => $Param{Email},
        %Param,
    );
    $Self->{QueueObject} = Kernel::System::Queue->new(%Param);
    $Self->{StateObject} = Kernel::System::State->new(%Param);
    $Self->{DestQueueObject} = Kernel::System::PostMaster::DestQueue->new(
        %Param,
        QueueObject => $Self->{QueueObject},
        ParseObject => $Self->{ParseObject},
    );
    $Self->{NewTicket} = Kernel::System::PostMaster::NewTicket->new(
        %Param,
        Debug => $Self->{Debug},
        ParseObject => $Self->{ParseObject},
        TicketObject => $Self->{TicketObject},
        QueueObject => $Self->{QueueObject},
        LoopProtectionObject => $Self->{LoopProtectionObject},
    );
    $Self->{FollowUp} = Kernel::System::PostMaster::FollowUp->new(
        %Param,
        Debug => $Self->{Debug},
        TicketObject => $Self->{TicketObject},
        LoopProtectionObject => $Self->{LoopProtectionObject},
        ParseObject => $Self->{ParseObject},
    );
    # should i use the x-otrs header?
    $Self->{Trusted} = defined $Param{Trusted} ? $Param{Trusted} : 1;

    return $Self;
}
# --
sub Run {
    my $Self = shift;
    my %Param = @_;
    # ConfigObject section / get params
    my $GetParam = $Self->GetEmailParams();

    # run all PreFilterModules (modify email params)
    if (ref($Self->{ConfigObject}->Get('PostMaster::PreFilterModule')) eq 'HASH') {
        my %Jobs = %{$Self->{ConfigObject}->Get('PostMaster::PreFilterModule')};
        foreach my $Job (sort keys %Jobs) {
            # log try of load module
            if ($Self->{Debug} > 1) {
                $Self->{LogObject}->Log(
                    Priority => 'debug',
                    Message => "Try to load module: $Jobs{$Job}->{Module}!",
                );
            }
            if (eval "require $Jobs{$Job}->{Module}") {
                my $FilterObject = $Jobs{$Job}->{Module}->new(
                    ConfigObject => $Self->{ConfigObject},
                    LogObject => $Self->{LogObject},
                    DBObject => $Self->{DBObject},
                    ParseObject => $Self->{ParseObject},
                    TicketObject => $Self->{TicketObject},
                    Debug => $Self->{Debug},
                );
                # log loaded module
                if ($Self->{Debug} > 1) {
                    $Self->{LogObject}->Log(
                        Priority => 'debug',
                        Message => "Module: $Jobs{$Job}->{Module} loaded!",
                    );
                }
                # modify params
                if (!$FilterObject->Run(
                    GetParam => $GetParam,
                    JobConfig => $Jobs{$Job},
                )) {
                    $Self->{LogObject}->Log(
                        Priority => 'error',
                        Message => "Execute Run() of $Jobs{$Job}->{Module} not successfully!",
                    );
                }
            }
            else {
                $Self->{LogObject}->Log(
                    Priority => 'error',
                    Message => "Can't load module $Jobs{$Job}->{Module}!",
                );
            }
        }
    }

    # should I ignore the incoming mail?
    if ($GetParam->{'X-OTRS-Ignore'} && $GetParam->{'X-OTRS-Ignore'} =~ /yes/i) {
       $Self->{LogObject}->Log(
           Priority => 'notice',
           Message => "Dropped Email (From: $GetParam->{'From'}, Message-ID: $GetParam->{'Message-ID'}) " .
           "because the X-OTRS-Ignore is set (X-OTRS-Ignore: $GetParam->{'X-OTRS-Ignore'})."
       );
       return 1;
   }
   # --
   # ticket section
   # --
   # check if follow up
   my ($Tn, $TicketID) = $Self->CheckFollowUp(%{$GetParam});
   # check if it's a follow up ...
   if ($Tn && $TicketID) {
        # get ticket data
        my %Ticket = $Self->{TicketObject}->TicketGet(TicketID => $TicketID);
        # check if it is possible to do the follow up
        # get follow up option (possible or not)
        my $FollowUpPossible = $Self->{QueueObject}->GetFollowUpOption(
            QueueID => $Ticket{QueueID},
        );
        # get lock option (should be the ticket locked - if closed - after the follow up)
        my $Lock = $Self->{QueueObject}->GetFollowUpLockOption(
            QueueID => $Ticket{QueueID},
        );
        # get state details
        my %State = $Self->{StateObject}->StateGet(ID => $Ticket{StateID});
        # create a new ticket
        if ($FollowUpPossible =~ /new ticket/i && $State{TypeName} =~ /^close/i) {
            $Self->{LogObject}->Log(
              Message => "Follow up for [$Tn] but follow up not possible($Ticket{State}).".
                " Create new ticket."
            );
            # send mail && create new article
            # get queue if of From: and To:
            if (!$Param{QueueID}) {
              $Param{QueueID} = $Self->{DestQueueObject}->GetQueueID(
                  Params => $GetParam,
              );
            }
            # check if trusted returns a new queue id
            my $TQueueID = $Self->{DestQueueObject}->GetTrustedQueueID(
                Params => $GetParam,
            );
            if ($TQueueID) {
                $Param{QueueID} = $TQueueID;
            }
            $Self->{NewTicket}->Run(
              InmailUserID => $Self->{PostmasterUserID},
              GetParam => $GetParam,
              QueueID => $Param{QueueID},
              Comment => "Because the old ticket [$Tn] is '$State{Name}'",
              AutoResponseType => 'auto reply/new ticket',
            );
            return 1;
        }
        # reject follow up
        elsif ($FollowUpPossible =~ /reject/i && $State{TypeName} =~ /^close/i) {
            $Self->{LogObject}->Log(
              Message=>"Follow up for [$Tn] but follow up not possible. Follow up rejected."
            );
            # send reject mail && and add article to ticket
            $Self->{FollowUp}->Run(
              TicketID => $TicketID,
              InmailUserID => $Self->{PostmasterUserID},
              GetParam => $GetParam,
              Lock => $Lock,
              Tn => $Tn,
              Comment => 'Follow up rejected.',
              AutoResponseType => 'auto reject',
            );
            return 1;
        }
        # create normal follow up
        else {
            $Self->{FollowUp}->Run(
              TicketID => $TicketID,
              InmailUserID => $Self->{PostmasterUserID},
              GetParam => $GetParam,
              Lock => $Lock,
              Tn => $Tn,
              AutoResponseType => 'auto follow up',
            );
        }
    }
    # create new ticket
    else {
        if ($Param{Queue} && !$Param{QueueID}) {
            # queue lookup if queue name is given
            $Param{QueueID} = $Self->{QueueObject}->QueueLookup(Queue => $Param{Queue});
        }
        # get queue if of From: and To:
        if (!$Param{QueueID}) {
            $Param{QueueID} = $Self->{DestQueueObject}->GetQueueID(Params => $GetParam);
        }
        # check if trusted returns a new queue id
        my $TQueueID = $Self->{DestQueueObject}->GetTrustedQueueID(
            Params => $GetParam,
        );
        if ($TQueueID) {
            $Param{QueueID} = $TQueueID;
        }
        $Self->{NewTicket}->Run(
            InmailUserID => $Self->{PostmasterUserID},
            GetParam => $GetParam,
            QueueID => $Param{QueueID},
            AutoResponseType => 'auto reply',
          );
        }
}
# --
# CheckFollowUp
# --
sub CheckFollowUp {
    my $Self = shift;
    my %Param = @_;
    my $Subject = $Param{Subject} || '';
    if (my $Tn = $Self->{TicketObject}->GetTNByString($Subject)) {
        my $TicketID = $Self->{TicketObject}->CheckTicketNr(Tn => $Tn);
        if ($Self->{Debug} > 1) {
            $Self->{LogObject}->Log(
                Priority => 'debug',
                Message => "CheckFollowUp: Tn: $Tn found or forward!",
            );
        }
        if ($TicketID) {
            if ($Self->{Debug} > 1) {
                $Self->{LogObject}->Log(
                  Priority => 'debug',
                  Message => "CheckFollowUp: ja, it's a follow up ($Tn/$TicketID)",
                );
            }
            return ($Tn, $TicketID);
        }
    }
    # There is no valid ticket number in the subject.
    # Try to find ticket number in References and In-Reply-To header.
    if ($Self->{ConfigObject}->Get('PostmasterFollowUpSearchInReferences')) {
        my @References = $Self->{ParseObject}->GetReferences();
        foreach (@References) {
            # get ticket id of message id
            my $TicketID = $Self->{TicketObject}->ArticleGetTicketIDOfMessageID(
                MessageID => "<$_>",
            );
            if ($TicketID) {
                my $Tn = $Self->{TicketObject}->TicketNumberLookup(
                     TicketID => $TicketID,
                );
                if ($TicketID && $Tn) {
                    return ($Tn, $TicketID);
                }
            }
        }
    }
    return;
}
# --
# GetEmailParams
# --
sub GetEmailParams {
    my $Self = shift;
    my %Param = @_;
    my %GetParam;
    # parse section
    my $WantParamTmp = $Self->{'PostmasterX-Header'} || die "Got no \@WantParam ref";
    my @WantParam = @$WantParamTmp;
    foreach (@WantParam){
      if (!$Self->{Trusted} && $_ =~ /^x-otrs/i) {
        # scan not x-otrs header if it's not trusted
      }
      else {
        if ($Self->{Debug} > 2) {
          $Self->{LogObject}->Log(
              Priority => 'debug',
              Message => "$_: " . $Self->{ParseObject}->GetParam(WHAT => $_),
          );
        }
        $GetParam{$_} = $Self->{ParseObject}->GetParam(WHAT => $_);
      }
    }
    # set compat. headers
    if ($GetParam{'Message-Id'}) {
        $GetParam{'Message-ID'} = $GetParam{'Message-Id'};
    }
    if ($GetParam{'Reply-To'}) {
        $GetParam{'ReplyTo'} = $GetParam{'Reply-To'};
    }
    if ($GetParam{'Mailing-List'} || $GetParam{'Precedence'} || $GetParam{'X-Loop'}
             || $GetParam{'X-No-Loop'} || $GetParam{'X-OTRS-Loop'}) {
        $GetParam{'X-OTRS-Loop'} = 'yes';
    }
    # set sender type if not given
    if (!$GetParam{'X-OTRS-SenderType'}) {
        $GetParam{'X-OTRS-SenderType'} = 'customer';
    }
    # check if X-OTRS-SenderType exists, if not, set customer
    if (!$Self->{TicketObject}->ArticleSenderTypeLookup(SenderType => $GetParam{'X-OTRS-SenderType'})) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message => "Can't find sender type '$GetParam{'X-OTRS-SenderType'}' in db, take 'customer'",
        );
        $GetParam{'X-OTRS-SenderType'} = 'customer';
    }
    # set article type f not given
    if (!$GetParam{'X-OTRS-ArticleType'}) {
        $GetParam{'X-OTRS-ArticleType'} = 'email-external';
    }
    # check if X-OTRS-ArticleType exists, if not, set 'email'
    if (!$Self->{TicketObject}->ArticleTypeLookup(ArticleType => $GetParam{'X-OTRS-ArticleType'})) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message => "Can't find article type '$GetParam{'X-OTRS-ArticleType'}' in db, take 'email-external'",
        );
        $GetParam{'X-OTRS-ArticleType'} = 'email-external';
    }
    # get body
    $GetParam{'Body'} = $Self->{ParseObject}->GetMessageBody();
    # get content type
    $GetParam{'Content-Type'} = $Self->{ParseObject}->GetReturnContentType();
    return \%GetParam;
}
# --
1;

# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::SupportDataCollector::Plugin::OTRS::ConfigSettings;

use strict;
use warnings;

use base qw(Kernel::System::SupportDataCollector::PluginBase);

use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::Config',
);

sub GetDisplayPath {
    return Translatable('OTRS') . '/' . Translatable('Config Settings');
}

sub Run {
    my $Self = shift;

    my @Settings = qw(
        Home
        FQDN
        HttpType
        DefaultLanguage
        SystemID
        Version
        ProductName
        Organization
        Ticket::IndexModule
        Ticket::SearchIndexModule
        Ticket::StorageModule
        SendmailModule
        Frontend::RichText
        Loader::Agent::DefaultSelectedSkin
        Loader::Customer::SelectedSkin
    );

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    for my $Setting (@Settings) {

        my $ConfigValue = $ConfigObject->Get($Setting);

        if ( defined $ConfigValue ) {
            $Self->AddResultInformation(
                Identifier => $Setting,
                Label      => $Setting,
                Value      => $ConfigValue,
            );
        }
        else {
            $Self->AddResultProblem(
                Identifier => $Setting,
                Label      => $Setting,
                Value      => $ConfigValue,
                Message    => Translatable('Could not determine value.'),
            );
        }
    }

    return $Self->GetResults();
}

1;

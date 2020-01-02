# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

# get helper object
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

# get command object
my $CommandObject = $Kernel::OM->Get('Kernel::System::Console::Command::Maint::Ticket::EscalationCheck');

my $ExitCode = $CommandObject->Execute();

$Self->Is(
    $ExitCode,
    0,
    "Maint::Ticket::EscalationCheck exit code",
);

# cleanup cache is done by RestoreDatabase

# It is also possible to capture the command output, see test/Console/Command/Maint/Config/Dump.t for an example.

1;

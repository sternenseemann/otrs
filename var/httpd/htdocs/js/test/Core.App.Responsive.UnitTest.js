// --
// Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (GPL). If you
// did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
// --

"use strict";

var Core = Core || {};
Core.App = Core.App || {};

Core.App.Responsive = (function (Namespace) {
    Namespace.RunUnitTests = function(){

        module('Core.App.Responsive');

        test('IsSmallerOrEqual', function(){
            expect(4);

            ok(Core.App.Responsive.IsSmallerOrEqual('ScreenL', 'ScreenXL'));
            ok(Core.App.Responsive.IsSmallerOrEqual('ScreenXS', 'ScreenL'));
            ok(Core.App.Responsive.IsSmallerOrEqual('ScreenM', 'ScreenM'));
            ok(!Core.App.Responsive.IsSmallerOrEqual('ScreenL', 'ScreenM'));
        });
    };

    return Namespace;
}(Core.App.Responsive || {}));

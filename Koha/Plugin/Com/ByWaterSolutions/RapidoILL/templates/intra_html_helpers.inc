[% USE raw %]

[% BLOCK rapido_docs_header %]
    [% INCLUDE 'doc-head-open.inc' %]
    <title>Rapido ILL - Configuration &rsaquo; Plugins &rsaquo; Administration &rsaquo; Koha</title>
    [% INCLUDE 'doc-head-close.inc' %]
    </head>

    <body>
    [% WRAPPER 'header.inc' %]
        [% INCLUDE 'cat-search.inc' %]
    [% END %]

    [% WRAPPER 'sub-header.inc' %]
        [% WRAPPER breadcrumbs %]
            [% WRAPPER breadcrumb_item %]
                <a href="/cgi-bin/koha/admin/admin-home.pl">Administration</a>
            [% END %]
            [% WRAPPER breadcrumb_item %]
                <a href="/cgi-bin/koha/plugins/plugins-home.pl">Plugins</a>
            [% END %]
            [% WRAPPER breadcrumb_item %]
                <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3AByWaterSolutions%3A%3ARapidoILL&method=admin">Rapido ILL</a>
            [% END %]
            [% WRAPPER breadcrumb_item bc_active=1 %]
                Configuration
            [% END %]
        [% END %]
    [% END %]
[% END %]

[% BLOCK rapido_config_errors %]
    [% IF errors %]
        [% FOREACH error IN errors %]
            <div class="dialog error">
                [% SWITCH error.code %]
                [% CASE 'ILLModule_disabled' %]<span>The <strong>mandatory</strong> system preference <a href="/cgi-bin/koha/admin/preferences.pl?op=search&searchfield=ILLModule" target="_blank">ILLModule<a> is disabled.</span>
                [% CASE 'CirculateILL_enabled' %]<span>The system preference <a href="/cgi-bin/koha/admin/preferences.pl?op=search&searchfield=CirculateILL" target="_blank">CirculateILL</a> is enabled, but it is incompatible with this plugin.</span>
                [% CASE 'missing_entry' %]<span>[<strong>[% error.pod | html %]</strong>] Missing configuration entry for <strong>[% error.value | html %]</strong></span>
                [% CASE 'undefined_partners_library_id' %]<span>[<strong>[% error.pod | html %]</strong>] The configured <strong>partners_library_id</strong> '[% error.value | html %]' is not defined on the system. Please define it <a href="/cgi-bin/koha/admin/branches.pl?op=add_form" target="_blank">here</a></span>
                [% CASE 'undefined_partners_category' %]<span>[<strong>[% error.pod | html %]</strong>] The configured <strong>partners_category</strong> '[% error.value | html %]' is not defined on the system. Please define it <a href="/cgi-bin/koha/admin/categories.pl?op=add_form" target="_blank">here</a></span>
                [% CASE 'undefined_default_item_type' %]<span>[<strong>[% error.pod | html %]</strong>] The configured <strong>default_item_type</strong> '[% error.value | html %]' is not defined on the system. Please define it <a href="/cgi-bin/koha/admin/itemtypes.pl?op=add_form" target="_blank">here</a></span>
                [% CASE 'undefined_central_item_type_mapping' %]<span>[<strong>[% error.pod | html %]</strong>] A <strong>central_item_type_mapping</strong> entry points to item type '[% error.value | html %]', which is not defined on the system. Please define it <a href="/cgi-bin/koha/admin/itemtypes.pl?op=add_form" target="_blank">here</a></span>
                [% CASE 'library_missing_description' %]<span>[<strong>[% error.pod | html %]</strong>] The configured <strong>library_to_location</strong> mapping for '[% error.library | html %]' is missing the <strong>description</strong>.</span>
                [% CASE 'library_missing_location' %]<span>[<strong>[% error.pod | html %]</strong>] The configured <strong>library_to_location</strong> mapping for '[% error.library | html %]' is missing the <strong>location</strong> code.</span>
                [% END %]
            </div>
        [% END %]
    [% END %]
[% END %]

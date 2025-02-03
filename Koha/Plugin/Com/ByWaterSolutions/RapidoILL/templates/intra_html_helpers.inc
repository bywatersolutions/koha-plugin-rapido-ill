[% USE raw %]

[% BLOCK rapido_docs_header %]
    [% INCLUDE 'doc-head-open.inc' %]
    <title>Koha: Rapido ILL</title>
    [% INCLUDE 'doc-head-close.inc' %]
    </head>

    <body>
    [% WRAPPER 'header.inc' %]
        [% INCLUDE 'cat-search.inc' %]
    [% END %]

    [% WRAPPER 'sub-header.inc' %]
        [% WRAPPER breadcrumbs %]
            [% WRAPPER breadcrumb_item %]
                <a href="/cgi-bin/koha/plugins/plugins-home.pl">Plugins</a>
            [% END %]
            [% WRAPPER breadcrumb_item %]
                <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3AByWaterSolutions%3A%3ARapidoILL&method=configure">Rapido ILL</a>
            [% END %]
        [% END #/ WRAPPER breadcrumbs %]
    [% END #/ WRAPPER sub-header.inc %]
[% END %]

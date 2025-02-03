[% USE Koha %]

[% SET report = job.decoded_data %]
[% BLOCK report %]
    [% IF job.status == 'finished' %]
        [% IF report %]
            <div class="dialog message">
                The item has been notified as received correctly.
            </div>
        [% ELSE %]
            <div class="dialog message">
               Job data could not be read, see the logs for details
            </div>
        [% END %]
    [% ELSIF job.status == 'cancelled' %]
        <span>The job has been cancelled before it finished.</span>
    [% END %]
[% END %]

[% BLOCK detail %]
    [% FOR m IN job.messages %]
        <div class="dialog message">
            [% IF m.type == 'success' %]
                <i class="fa fa-check success"></i>
            [% ELSIF m.type == 'warning' %]
                <i class="fa-solid fa-triangle-exclamation warn"></i>
            [% ELSIF m.type == 'error' %]
                <i class="fa fa-exclamation error"></i>
            [% END %]
            [% SWITCH m.code %]
                [% CASE 'request_failed' %]
                    <span>Error sending <b>[% m.method | html %]</b> request: [% m.response | html %]<span>
            [% CASE %]
                    <span>Unhandled error: [% m.error | html %]<span>
            [% END %]
        </div>
    [% END %]
[% END %]


[% BLOCK js %]
[% END %]

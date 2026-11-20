[%# Template for borrower_cancel action %]
[% IF whole.value.error_message && whole.value.allow_force %]
<div class="alert alert-warning">
    [% IF whole.value.already_cancelled %]
        <p><strong>Warning:</strong> Rapido reports this request cannot be cancelled through their system.</p>
        <p>[% whole.message | html %]</p>
        <p>This typically means the request was already cancelled on Rapido's side but the update wasn't synchronized.</p>
    [% ELSE %]
        <p><strong>Warning:</strong> Rapido could not cancel this request.</p>
        <p>[% whole.message | html %]</p>
        <p>If this looks like a temporary problem, try cancelling again later. Only force cancel if the request can't be cancelled through Rapido.</p>
    [% END %]
    <p>You can force cancel this request locally, which will update the status in Koha without notifying Rapido.</p>
</div>

<form method="post" action="/cgi-bin/koha/ill/ill-requests.pl" id="cancel-form">
    [% INCLUDE 'csrf-token.inc' %]
    <input type="hidden" name="illrequest_id" value="[% request.illrequest_id | html %]" />
    <input type="hidden" name="method" value="borrower_cancel" />
    <input type="hidden" name="backend" value="RapidoILL" />
    <input type="hidden" name="force_cancel" value="1" />

    <fieldset class="action">
        <button type="submit" class="btn btn-danger">
            <i class="fa fa-exclamation-triangle"></i> Force Cancel
        </button>
        <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">Return</a>
    </fieldset>
</form>
[% ELSIF whole.value.error_message %]
<div class="alert alert-danger">
    <p><strong>Error:</strong> [% whole.value.error_message | html %]</p>
    [% IF whole.value.already_cancelled %]
        <p>The request may have already been cancelled on Rapido's side. A staff member allowed to force cancel can cancel it locally.</p>
    [% END %]
</div>
<p>Try again?</p>
[% ELSE %]
<p>Cancel this ILL request?</p>
[% END %]

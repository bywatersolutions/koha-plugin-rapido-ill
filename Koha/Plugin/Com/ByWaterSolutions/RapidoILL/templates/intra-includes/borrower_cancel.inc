[%# Template for borrower_cancel action %]
[% IF whole.value.error_message && !whole.value.allow_force %]
    <div class="alert alert-danger">
        <p><strong>Error:</strong> [% whole.value.error_message | html %]</p>
    </div>
    <p>Try again?</p>
[% ELSIF whole.value.allow_force %]
    <div class="alert alert-warning">
        <p><strong>Warning:</strong> Rapido reports this request cannot be cancelled through their system.</p>
        <p>[% whole.message | html %]</p>
        <p>This typically means the request was already cancelled on Rapido's side but the update wasn't synchronized.</p>
        <p>You can force cancel this request locally, which will update the status in Koha without notifying Rapido.</p>
    </div>

    <form method="post" action="/cgi-bin/koha/ill/ill-requests.pl" id="cancel-form">
        [% INCLUDE 'csrf-token.inc' %]
        <input type="hidden" name="illrequest_id" value="[% request.illrequest_id | html %]" />
        <input type="hidden" name="method" value="borrower_cancel" />
        <input type="hidden" name="backend" value="RapidoILL" />
        <input type="hidden" name="force_cancel" value="1" />

        <fieldset class="action">
            <button type="submit" class="btn btn-danger"> <i class="fa fa-exclamation-triangle"></i> Force Cancel </button>
            <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">Cancel Operation</a>
        </fieldset>
    </form>
[% ELSE %]
    <p>Cancel this ILL request?</p>
[% END %]

[%# Template for force_complete_lender action %]
[% IF whole.stage == "init" %]
<div class="alert alert-warning">
    <h4><i class="fa fa-exclamation-triangle"></i> Force complete (local only)</h4>
    <p>This will complete the lending request locally <strong>without notifying Rapido</strong>. Use this only when the request is stuck due to messaging issues with Rapido.</p>
    <p>The following actions will be performed:</p>
    <ul>
        <li>Check in the item (if currently checked out)</li>
        <li>Cancel any associated hold for the ILL patron</li>
        <li>Mark request as completed</li>
    </ul>
    <p><strong>This action cannot be undone.</strong></p>
</div>

<form method="post" action="/cgi-bin/koha/ill/ill-requests.pl" id="force-complete-lender-form">
    [% INCLUDE 'csrf-token.inc' %]
    <input type="hidden" name="illrequest_id" value="[% request.illrequest_id | html %]" />
    <input type="hidden" name="method" value="force_complete_lender" />
    <input type="hidden" name="backend" value="RapidoILL" />
    <input type="hidden" name="confirmed" value="1" />
    <input type="hidden" name="stage" value="confirm" />

    <fieldset class="action">
        <button type="submit" class="btn btn-danger">
            <i class="fa fa-exclamation-triangle"></i> Force complete
        </button>
        <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">Cancel</a>
    </fieldset>
</form>
[% ELSE %]
<p>Unknown stage.</p>
[% END %]

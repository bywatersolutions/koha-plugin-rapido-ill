[%# Template for item_in_transit action %]
[% IF whole.error %]
<div class="alert alert-danger">
    <p><strong>Error:</strong> [% whole.message | html %]</p>
</div>

<div class="alert alert-warning">
    <p>Rapido rejected the notification. This typically means Rapido already considers this item in transit or the request has been closed on their side.</p>
    <p>You can force this action locally without notifying Rapido.</p>
</div>

<form method="post" action="/cgi-bin/koha/ill/ill-requests.pl" id="force-item-in-transit-form">
    [% INCLUDE 'csrf-token.inc' %]
    <input type="hidden" name="illrequest_id" value="[% request.illrequest_id | html %]" />
    <input type="hidden" name="method" value="item_in_transit" />
    <input type="hidden" name="backend" value="RapidoILL" />
    <input type="hidden" name="force_local" value="1" />
    <input type="hidden" name="stage" value="confirm" />

    <fieldset class="action">
        <button type="submit" class="btn btn-warning">
            <i class="fa fa-exclamation-triangle"></i> Force item in transit (local only)
        </button>
        <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">Cancel</a>
    </fieldset>
</form>
[% ELSE %]
<p>Mark this item as in transit?</p>
[% END %]

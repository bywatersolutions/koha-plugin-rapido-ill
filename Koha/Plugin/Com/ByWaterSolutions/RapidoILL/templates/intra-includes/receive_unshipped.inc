[% IF whole.error %]
<p>Unhandled error</p>
[% END %]

[% IF whole.stage == "form" %]
<h2>Receive item (unshipped)</h2>
<p>The item has been received by the library but no precedent <i>itemshipped</i> message received.</p>
<p>
  [% base_url = "/cgi-bin/koha/ill/ill-requests.pl" %]
  [% proceed_url = base_url _ "?method=receive_unshipped&stage=confirm" _
                   "&illrequest_id=" _ request.illrequest_id %]
  <form id="rapido_receiveunshipped_form" method="POST" action=[% proceed_url %]>
      [% INCLUDE 'csrf-token.inc' %]
      <input type="hidden" name="op"      value="cud-receive_unshipped" />
      <input type="hidden" name="method"  value="receive_unshipped" />
      <input type="hidden" name="stage"   value="confirm" />
      <input type="hidden" name="backend" value="RapidoILL" />
      <input type="hidden" name="illrequest_id" value="[% request.illrequest_id %]" />
            <fieldset class="rows">
            <ol>
                <li>
                    <label for="item_barcode" class="required">Barcode: </label>
                    <input type="text" name="item_barcode" id="item_barcode" size="60" class="required"/>
                    <span class="required">Required</span>
                </li>
                <li>
                    <label for="item_callnumber" class="required">Call number: </label>
                    <input type="text" name="item_callnumber" id="item_callnumber" size="60" class="required"/>
                    <span class="required">Required</span>
                </li>
            </ol>
        </fieldset>
        <fieldset class="action">
            <input type="submit" value="Submit" />
            <a class="cancel" href="[% base_url %]">Cancel</a>
        </fieldset>

  </form>
</p>

[% ELSE %]
<p>Unknown stage.  This should not have happened.
[% END %]

[% IF whole.error %]
<p>Unhandled error</p>
[% END %]

[% IF whole.stage == "form" %]
<h2>Specify the recall due date</h2>
<p>Proceeding with this action will set this request to 'Recalled'.</p>
<p>
  [% base_url = "/cgi-bin/koha/ill/ill-requests.pl" %]
  [% proceed_url = base_url _ "?method=item_recalled&stage=confirm" _
                   "&illrequest_id=" _ request.illrequest_id %]
    <form id="rapido_recall_form" method="POST" action=[% proceed_url %]>
        [% INCLUDE 'csrf-token.inc' %]
        <input type="hidden" name="op"     value="cud-item_recalled" />
        <input type="hidden" name="method" value="item_recalled" />
        <input type="hidden" name="stage" value="confirm" />
        <input type="hidden" name="backend" value="RapidoILL" />
        <input type="hidden" name="illrequest_id" value="[% request.illrequest_id %]" />
        <fieldset class="rows">
            <ol>
                <li>
                    <label for="recall_due_date" class="required">Due datet: </label>
                    <input type="text" name="recall_due_date" id="recall_due_date" size="60" class="required datepicker"/>
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

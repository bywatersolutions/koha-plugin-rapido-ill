[% IF whole.error %]
    [% IF whole.status == 'invalid_due_date' %]
        <div class="alert alert-danger">
            <strong>Invalid due date:</strong> [% whole.message | html %]
        </div>
    [% ELSIF whole.status == 'error_on_renewal' %]
        <div class="alert alert-danger">
            <strong>Renewal processing error:</strong> [% whole.message | html %]
        </div>
    [% ELSE %]
        <div class="alert alert-danger">
            <strong>Error:</strong> [% whole.message | html %]
        </div>
    [% END %]
[% END %]

[% IF whole.stage == "form" %]
    <h2>Handle renewal request</h2>

    [% IF whole.value.borrower_requested_due_date %]
        <p><strong>Borrower requested due date:</strong> [% whole.value.borrower_requested_due_date | $KohaDates %]</p>
    [% END %]

    <form method="post" action="/cgi-bin/koha/ill/ill-requests.pl" id="renewal-form">
        [% INCLUDE 'csrf-token.inc' %]
        <input type="hidden" name="illrequest_id" value="[% request.illrequest_id | html %]" />
        <input type="hidden" name="method" value="renewal_request" />
        <input type="hidden" name="stage" value="confirm" />
        <input type="hidden" name="backend" value="RapidoILL" />
        <input type="hidden" name="decision" id="decision-input" />

        <fieldset class="rows">
            <ol>
                <li>
                    <label>
                        <input type="checkbox" id="override-date" />
                        <strong>Override with custom due date</strong>
                    </label>
                    <div class="hint">Check this box to set a different due date than the borrower requested</div>
                </li>
                <li id="custom-date-section" style="display: none;">
                    <label for="new_due_date">Custom due date:</label>
                    <input type="text" name="new_due_date" id="new_due_date" class="flatpickr" data-flatpickr-futuredate="true" size="10" />
                    <div class="hint">This will override the borrower's requested date</div>
                </li>
            </ol>
        </fieldset>

        <fieldset class="action">
            <button type="button" class="btn btn-primary" onclick="approveRenewal()">
                <i class="fa fa-check"></i> Approve Renewal
            </button>
            <span title="Koha is not allowed to reject renewals">
                <button type="button" class="btn btn-danger" disabled>
                    <i class="fa fa-times"></i> Reject Renewal
                </button>
            </span>
            <a class="cancel" href="/cgi-bin/koha/ill/ill-requests.pl?method=illview&amp;illrequest_id=[% request.illrequest_id | uri %]">Cancel</a>
        </fieldset>
    </form>

    <script>
    // Use DOMContentLoaded instead of $(document).ready() because jQuery may not be loaded
    // when this template is inserted into the main Koha ILL request template
    document.addEventListener('DOMContentLoaded', function() {
        // Show/hide custom date section
        $('#override-date').change(function() {
            if ($(this).is(':checked')) {
                $('#custom-date-section').show();
            } else {
                $('#custom-date-section').hide();
                $('#new_due_date').val('');
            }
        });
    });

    function approveRenewal() {
        $('#decision-input').val('approve');
        $('#renewal-form').submit();
    }
    </script>

[% ELSE %]
    <p>Unknown stage. This should not have happened.</p>
[% END %]

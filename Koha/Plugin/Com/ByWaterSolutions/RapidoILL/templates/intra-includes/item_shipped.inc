[% IF whole.error %]
    [% IF whole.status == 'error_on_checkout' %]
        <p>There was an <strong>error</strong> checking out the item ([% whole.message | html %]).</p>
    [% END %]
[% END %]

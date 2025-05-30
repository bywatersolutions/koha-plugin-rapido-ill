# koha-plugin-rapido-ill

## Plugin configuration

The plugin configuration is an HTML text area in which a *YAML* structure is pasted. The available options
are maintained on this document.

```yaml
---
dev03-na:
  base_url: https://dev03-na.alma.exlibrisgroup.com
  client_id: client_id
  client_secret: client_secret
  server_code: 11747
  partners_library_id: CPL
  partners_category: ILL
  default_item_type: ILL
  default_patron_agency: code1
  default_location:
  default_checkin_note: Additional processing required (ILL)
  default_hold_note: Placed by ILL
  default_marc_framework: FA
  default_item_ccode: RAPIDO
  default_notforloan:
  materials_specified: true
  default_materials_specified: Additional processing required (ILL)
  location_to_library:
    RES_SHARE: CPL
  borrowing:
    automatic_item_in_transit: false
    automatic_item_receive: false
  lending:
    automatic_final_checkin: false
    automatic_item_shipped: false
  # Patron validation restrictions
  debt_blocks_holds: true
  max_debt_blocks_holds: 100
  expiration_blocks_holds: true
  restriction_blocks_holds: true
  # Debugging
  debug_mode: false
  debug_requests: false
  dev_mode: false
  default_retry_delay: 120
```

## Setting the task queue daemon

The task queue daemon will process any asynchronous tasks that are required.
This will usually relate to circulation updates to be notified to the pod.

To run it:

```shell
$ cp /var/lib/koha/<instance>/plugins/Koha/Plugin/Com/ByWaterSolutions/RapidoILL/scripts/rapido_task_queue.service \
     /etc/systemd/system/rapido_task_queue.service
# set KOHA_INSTANCE to match what you need (default: kohadev)
$ vim /etc/systemd/system/rapido_task_queue.service
# reload unit files, including the new one
$ systemctl daemon-reload
# enable service
$ systemctl enable rapido_task_queue.service
Created symlink /etc/systemd/system/multi-user.target.wants/rapido_task_queue.service → /etc/systemd/system/rapido_task_queue.service
# check the logs :-D
$ journalctl -u rapido_task_queue.service -f
```

## Notices

The plugin implements the `notices_content` hook to make ILL-related information available to notices.

### `HOLD_SLIP`

On this letter, the plugin makes this attributes available.

* `[% plugin_content.rapidoill.ill_request %]`
* `[% plugin_content.rapidoill.author | html %]`
* `[% plugin_content.rapidoill.borrowerCode | html %]`
* `[% plugin_content.rapidoill.callNumber | html %]`
* `[% plugin_content.rapidoill.circ_action_id | html %]`
* `[% plugin_content.rapidoill.circId | html %]`
* `[% plugin_content.rapidoill.circStatus | html %]`
* `[% plugin_content.rapidoill.dateCreated | html %]`
* `[% plugin_content.rapidoill.dueDateTime | html %]`
* `[% plugin_content.rapidoill.itemAgencyCode | html %]`
* `[% plugin_content.rapidoill.itemBarcode | html %]`
* `[% plugin_content.rapidoill.itemId | html %]`
* `[% plugin_content.rapidoill.lastCircState | html %]`
* `[% plugin_content.rapidoill.lastUpdated | html %]`
* `[% plugin_content.rapidoill.lenderCode | html %]`
* `[% plugin_content.rapidoill.needBefore | html %]`
* `[% plugin_content.rapidoill.patronAgencyCode | html %]`
* `[% plugin_content.rapidoill.patronId | html %]`
* `[% plugin_content.rapidoill.patronName | html %]`
* `[% plugin_content.rapidoill.pickupLocation | html %]`
* `[% plugin_content.rapidoill.pod | html %]`
* `[% plugin_content.rapidoill.puaLocalServerCode | html %]`
* `[% plugin_content.rapidoill.title | html %]`

The `ill_request` attribute will only be available if the plugin finds the hold is linked to
a valid Rapido ILL request. It should be used to detect the ILL context for displaying
ILL specific messages.

For example:

```
[% IF plugin_content.rapidoill.ill_request  %]
<ul>
    <li>ILL request ID: [% plugin_content.rapidoill.ill_request.id | html %]</li>
    <li>Item ID: [% plugin_content.rapidoill.itemId | html %]</li>
    <li>Pickup location: [% plugin_content.rapidoill.pickupLocation | html %]</li>
    <li>Patron name: [% plugin_content.rapidoill.patronName | html %]</li>
    <li>Call number: [% plugin_content.rapidoill.callNumber | html %]</li>
<ul>
[% END %]
```
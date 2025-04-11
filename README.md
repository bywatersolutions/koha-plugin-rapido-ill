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
    automatic_item_shipped_debug: false
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

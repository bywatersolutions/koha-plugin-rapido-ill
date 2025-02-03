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
  partners_library_id: CPL
  partners_category: ILL
  default_patron_agency: code1
  default_location:
  default_checkin_note: Additional processing required (ILL)
  default_hold_note: Placed by ILL
  default_marc_framework: FA
  default_item_ccode: RAPIDO
  default_notforloan:
  materials_specified: true
  default_materials_specified: Additional processing required (ILL)
  local_to_central_itype:
    BK: 200
    CF: 201
    CR: 200
    MP: 200
    MU: 201
    MX: 201
    REF: 202
    VM: 201
  local_to_central_patron_type:
    AP: 200
    CH: 200
    DR: 200
    DR2: 200
    ILL: 202
    LIBSTAFF: 201
    NR: 200
    SR: 202
  central_to_local_itype:
    200: D2IR_BK
    201: D2IR_CF
  no_barcode_central_itypes:
    - 201
    - 202
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

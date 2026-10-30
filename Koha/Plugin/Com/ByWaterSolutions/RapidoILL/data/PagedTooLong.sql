SELECT b.title, i.barcode, r.status, r.updated, p.borrowernumber AS 'borrower', r.illrequest_id

FROM illrequests r 
LEFT JOIN biblio b on r.biblio_id=b.biblionumber
LEFT JOIN items i on b.biblionumber=i.biblionumber
LEFT JOIN borrowers p on r.borrowernumber=p.borrowernumber

WHERE r.backend="Rapido" AND r.status="O_ITEM_REQUESTED" AND date(r.updated) <  <<Last updated before|date>> 
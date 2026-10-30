SELECT  a.value, r.status, r.updated, p.borrowernumber AS 'borrower', r.illrequest_id 

FROM illrequests r 
LEFT JOIN biblio b on r.biblio_id=b.biblionumber
LEFT JOIN items i on b.biblionumber=i.biblionumber
LEFT JOIN borrowers p on r.borrowernumber=p.borrowernumber
LEFT JOIN illrequestattributes a on r.illrequest_id=a.illrequest_id

WHERE r.backend="Rapido" AND r.status="B_ITEM_REQUESTED" AND date(r.updated) <  <<Last updated before|date>>  AND a.type='title'
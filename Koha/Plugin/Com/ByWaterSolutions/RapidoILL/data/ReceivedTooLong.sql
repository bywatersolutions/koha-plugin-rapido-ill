SELECT b.title, i.barcode, r.status, r.updated
FROM reserves h 
left join biblio b on h.biblionumber=b.biblionumber
left join items i on h.itemnumber=i.itemnumber
LEFT JOIN borrowers p ON h.borrowernumber=p.borrowernumber
left join illrequestattributes a ON h.reserve_id=a.value
left join illrequests r on a.illrequest_id=r.illrequest_id
WHERE p.categorycode="ILL" AND date(h.waitingdate) <  <<Holds waiting before|date>>  AND a.type="hold_id"
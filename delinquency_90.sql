--extracting loan has delinquency value >=3
WITH del_90 AS(
SELECT new_pef.loan_identifier,new_pef.current_loan_delinquency_status from new_pef 
WHERE current_loan_delinquency_status not in ('0', '1', '2', 'X')),
del_id as (
SELECT distinct loan_identifier from del_90),                   --unique the loan id
del_per_loan as (
SELECT ac.*, CASE WHEN d.loan_identifier is not null THEN 1
	              WHEN d.loan_identifier is null then 0
	              END AS D_90_FLAG
FROM fannie_mae.Acquisition ac LEFT JOIN                  ---join the delinquency status with acuisition file
del_id AS d ON ac.loan_identifier=d.loan_identifier)
select * into delinq_status 



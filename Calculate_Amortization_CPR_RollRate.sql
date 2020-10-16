-- show performance,acquisition data
SELECT * FROM fannie_mae.Performance limit 100;
SELECT * FROM fannie_mae.Acquisition limit 100;


-- check paid off prepayment
select loan_identifier,monthly_reporting_period, current_actual_upb,
		zero_balance_code, zero_balance_effective_date
from fannie_mae.Performance
WHERE zero_balance_code='01';

select loan_identifier,monthly_reporting_period, current_actual_upb,
		zero_balance_code, zero_balance_effective_date
from fannie_mae.Performance
WHERE zero_balance_code='01' and current_actual_upb !=0; 

--set loan current upb to 0 where zero_balance code is '01'
update fannie_mae.Performance
set current_actual_upb = 0::float8
WHERE zero_balance_code='01' and current_actual_upb !=0;


--drop zero balance code is 06 or 16, since these loans are sold
Delete FROM fannie_mae.Performance WHERE zero_balance_code ='06';
Delete FROM fannie_mae.Performance WHERE zero_balance_code ='16';
SELECT * FROM fannie_mae.Performance;


----calculate the amortization,smm
WITH perf_pre_upb AS(
SELECT *, lag(p.current_actual_upb) OVER (PARTITION BY p.loan_identifier order by p.monthly_reporting_period) pre_month_upb
FROM fannie_mae.Performance p),
Amortization AS(
SELECT pf.loan_identifier,pf.monthly_reporting_period, pf.current_interest_rate,
	   ac.original_upb,ac.original_interest_rate,
(ac.original_upb*ac.original_interest_rate/1200*(1+ac.original_interest_rate/1200)^ac.original_loan_term/((1+ac.original_interest_rate/1200)^ac.original_loan_term-1)) as amortization,
(pf.pre_month_upb*ac.original_interest_rate/1200) as interest,
((ac.original_upb*ac.original_interest_rate/1200*(1+ac.original_interest_rate/1200)^ac.original_loan_term/((1+ac.original_interest_rate/1200)^ac.original_loan_term-1))- (pf.pre_month_upb*ac.original_interest_rate/1200)) as scheduled_Prin,
pf.current_actual_upb,	   
pf.pre_month_upb,
pf.pre_month_upb - pf.current_actual_upb as actual_Prin
FROM perf_pre_upb as pf
LEFT JOIN fannie_mae.Acquisition AS ac ON
pf.loan_identifier=ac.loan_identifier),
schedule AS(
SELECT am.*,am.actual_Prin-am.scheduled_Prin  pre_paid,
       am.pre_month_upb-am.scheduled_Prin scheduled_remain,
	 ((am.actual_Prin-am.scheduled_Prin)/(am.pre_month_upb-am.scheduled_Prin))  smm
FROM Amortization AS am)
SELECT * INTO NEW_prepaid_curtial_all from schedule  --extract all value into a new table named schedule

--check data
SELECT * FROM NEW_prepaid_curtial_all;

----calcualte cpr 
create table new_cpr_paid_off as
select monthly_reporting_period,
		sum(smm)/count(smm)as avg_smm_month,
		(1-(1-(sum(smm)/count(smm)))^12) as CPR_per_Month
from NEW_prepaid_curtial_all
group by monthly_reporting_period;
SELECT * FROM new_cpr_paid_off;

------calculate the delinquency roll rate
--check delingquency status by month, group by month and delinquency status
SELECT monthly_reporting_period,current_loan_delinquency_status,COUNT(loan_identifier)
FROM fannie_mae.Performance GROUP BY monthly_reporting_period,current_loan_delinquency_status;

-------------------------create delinquency performance
with pf_new AS(
SELECT loan_identifier,monthly_reporting_period,current_loan_delinquency_status,zero_balance_code,foreclosure_date,
       case when current_loan_delinquency_status in ('0','1','2','3') then current_loan_delinquency_status
	        WHEN current_loan_delinquency_status IS NOT NULL AND current_loan_delinquency_status NOT IN ('0','1','2','3','X') THEN '4+'
			WHEN zero_balance_code='01' THEN 'P'
			WHEN foreclosure_date is not NULL or zero_balance_code in ('03','09') THEN 'F'
			WHEN zero_balance_code in ('02','06','15','16') then 'O'
            END AS performance
FROM fannie_mae.Performance)
SELECT * into deliq_status from pf_new;								   ; 									  

update deliq_status
set performance='O'   --O means others
WHERE performance is null;

SELECT performance,COUNT(*) from deliq_status group by performance;
SELECT * FROM deliq_status;

--use crosstab to create delinquency rollrate table
CREATE EXTENSION tablefunc;
CREATE TABLE del_rollrate as
SELECT * FROM crosstab(
	'select loan_identifier,monthly_reporting_period,performance from deliq_status order by 1,2',
    'select distinct monthly_reporting_period from deliq_status order by 1')
AS ct(loan_identifer text, Jan18 text, Feb18 text,Mar18 text,
				  Apr18 text, May18 text, Jun18 text, July18 text, Aug18 text,Sep18 text,
				  Oct18 text, Nov18 text, Dec18 text, Jan19 text, Feb19 text, Mar19 text,
                  Apr19 text, May19 text, June19 text, July19 text, Aug19 text, Sep19 text,
                  Oct19 text, Nov19 text, Dec19 text);
				  
SELECT * FROM del_rollrate;
SELECT aug18,count(*) from del_rollrate group by aug18;

-- calculate roll rate Aug18 and Aug19
CREATE EXTENSION tablefunc;
SELECT * from crosstab( 'select aug18,sep18, count(*)
					   FROM del_rollrate where aug18 is not null and sep18 is not null
					   group by (aug18,sep18) order by 1,2',
					  'select distinct aug18 from del_rollrate where aug18 is not null order by 1')
as ct(aug18 text, "0" bigint, "1" bigint, "2" bigint, "3" bigint, "4+" bigint, Other bigint, P bigint);


----------------------------------------------------------------------------------

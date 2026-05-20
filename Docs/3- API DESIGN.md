1- Mapping entities to URI's


| Entity              | URI                                                |
| ------------------- | -------------------------------------------------- |
| Company             | /companies                                         |
| Employee            | /employees                                         |
| Payroll Run         | /payroll-runs                                      |
| Country Tax Rule    | /country-tax-rules                                 |
| Payment Method      | /payment-methods                                   |
| Payroll Intent      | /payroll-runs/:id/intents                          |
| Payslip             | /payroll-runs/:id/payslips /employees/:id/payslips |
| Invoice             | /companies/:id/invoices                            |
| Company Transaction | /companies/:id/transactions /companies/:id/deposit |


2- Defining Resources Representation


| Entity              | Representation                                                                                                                                                                     |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Company             | { id, name, country, billing_email, balance (computed), status, inserted_at, updated_at }                                                                                          |
| Employee            | { id, company_id, country_tax_id, name, email, gross_salary, status, inserted_at, updated_at }                                                                                     |
| Payroll Run         | { id, company_id, pay_period, status, error, total_amount, ran_at, inserted_at, updated_at }                                                                                       |
| Payroll Intent      | { id, payroll_run_id, employee_id, gross_salary, income_tax, social_security, net_salary, platform_fee, status, error, retry_count, provider_payment_id, inserted_at, updated_at } |
| Payslip             | { id, payroll_intent_id, employee_id, pay_period, gross_salary, income_tax, social_security, net_salary, generated_at, inserted_at }                                               |
| Invoice             | { id, company_id, payroll_run_id, total_gross_salaries, total_taxes_withheld, total_platform_fees, total_amount, status, issued_at, paid_at, inserted_at, updated_at }             |
| Country Tax Rule    | { id, country_code, country_name, income_tax_rate, social_security_rate, currency, inserted_at }                                                                                   |
| Payment Method      | { id, employee_id, bank_name, account_holder, account_number, bank_code, is_default, inserted_at, updated_at }                                                                     |
| Company Transaction | { id, company_id, amount, type, reference_id, description, inserted_at }                                                                                                           |


3- Assigning http methods to each resource


| Entity              | HTTP Methods                                                                                          |
| ------------------- | ----------------------------------------------------------------------------------------------------- |
| Company             | GET /companies, POST /companies, PUT /companies                                                     |
| Employee            | GET /employees, POST /employees, PUT /employees                                                     |
| Payroll Run         | GET /payroll-runs, GET /payroll-runs/:id, POST /payroll-runs                                        |
| Payroll Intent      | GET /payroll-runs/:id/intents                                                                         |
| Payslip             | GET /payroll-runs/:id/payslips, GET /employees/:id/payslips                                          |
| Invoice             | GET /companies/:id/invoices, GET /companies/:id/invoices/:invoice_id                                 |
| Country Tax Rule    | GET /country-tax-rules, PUT /country-tax-rules/:id                                                   |
| Payment Method      | GET /payment-methods, POST /payment-methods, PUT /payment-methods/:id, DELETE /payment-methods/:id |
| Company Transaction | GET /companies/:id/transactions, POST /companies/:id/deposit                                         |


4- Extra resources needed


| Resource                  | HTTP Method |
| ------------------------- | ----------- |
| /payroll-runs/:id/start   | POST        |
| /payroll-runs/:id/approve | POST        |
| /payroll-runs/:id/cancel  | POST        |



# navesti
Navesti is Sorbet's DSL used to integrate to any type of backend integrations


# REVOLUT OB CLIENT

## Overview

This is a Ruby client for the Revolut Open Banking API.


# Run the code

- At the moment
    - make test_accounts # Runs only the Accounts test suite
    - make test_transactions # Runs only the Transactions test suite
    - make test # Runs all the test suites

# INFORMATIONS BEFORE RUNNING THE CODE

- You need to have a Revolut account in the Revolut Developer portal
- You need to type the 6 digit code you receive in your email to login
- After logging in, you need to create an application to test your code in the developer portal
- There you must fill or see:
    1. Redirect urls -> Urls to redirect after the authorisation process
    2. Your sandbox certificates -> Upload the CSR file
    3. At any time you can check or uncheck the Open Banking API Scopes
    4. On Test Accounts section you will find the 
        1. Number and password needed for every authorisation.
        2. Number is 7258777150 --->(+44)<---
        3. Password is 0000
    5. The Client ID for the sandbox environment in the Overview section
    6. JWKs endpoint
        1. There you should place the JWKs URL that you store the jwks.json and the private key.
        You need that URL to be a public url so that the Revolut API can access it.

# Use my settings if you want

- If you want to use my existing account, ask for the email and password 


# Flow

- If all are set up correctly, you can run the code
    1.  make test
    2.  copy paste the number and password
    3.  accept the authorisation
    4.  wait for the redirection, then copy paste the redirected url to the terminal (it waits for you)
    5.  repeat steps 2,3,4 until the flow ends
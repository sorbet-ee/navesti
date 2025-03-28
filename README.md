# navesti
Navesti is Sorbet's DSL used to integrate to any type of backend integrations


# REVOLUT OB CLIENT

## Overview

This is a Ruby client for the Revolut Open Banking API.

## Methods

1. get_access_token

Gets an access_token. Stores it in test_results/access_token.json

2. create_an_account_access_consent

Create an account access consent. Stores it in test_results/account_access_consent.json. We need the consent_id from this response to retrieve the account access consent. (start the authorization process)

3. retrieve_an_account_access_consent

Retrieve an account access consent. We need the consent_id from the previous response to retrieve the account access consent. (start the authorization process)

4. get_consent_from_the_user

Redirects us to Revolut's authorization page. We make the url.
It consists of:
- response_type: code id_token
- scope: accounts
- redirect_uri: https://example.com
- client_id: d099c903-2443-410e-844e-7282c6ec118f
- request: jwt


Example:  https://sandbox-oba.revolut.com/ui/index.html?response_type=code%20id_token&scope=accounts&redirect_uri=https://example.com&client_id=d099c903-2443-410e-844e-7282c6ec118f&request=eyJhbGciOiJQUzI1NiIsImtpZCI6IjAwNyJ9.InJlc3BvbnNlX3R5cGU9Y29kZStpZF90b2tlbiZjbGllbnRfaWQ9ZDA5OWM5MDMtMjQ0My00MTBlLTg0NGUtNzI4MmM2ZWMxMThmJnJlZGlyZWN0X3VyaT1odHRwcyUzQSUyRiUyRmV4YW1wbGUuY29tJmF1ZD1odHRwcyUzQSUyRiUyRnNhbmRib3gtb2JhLWF1dGgucmV2b2x1dC5jb20mc2NvcGU9YWNjb3VudHMmc3RhdGU9NThmZjFkMWQtZWJmMi00MWIxLTk3ZmUtYmU2MDUyYWY1MjNmJm5iZj0xNzM4MTU4NjUzJmV4cD0xNzM4MTYxOTUzJmNsYWltcz0lN0IlMjJpZF90b2tlbiUyMiUzRCUzRSU3QiUyMm9wZW5iYW5raW5nX2ludGVudF9pZCUyMiUzRCUzRSU3QiUyMnZhbHVlJTIyJTNEJTNFJTIyNTM0YjAwYmMtMDk4Yi00NGU4LWJhYzAtMDc5ZmY0MzFkMzRiJTIyJTdEJTdEJTdEIg.edNEyPYzdSVZlAieWPr-RQ3po3TdPSzaMOEoD7TpLKXkEyx0n-ttyYOLp2tMMZ4tNktO5YndkSYX2mDJ3S2SBPuZbZQ0zEje60tlMssaZI2upGwkLvYpstB3IAGFxeyh755FX78Eb48KMJ1WC2uMMpV_33avWka-bJFfVOZ97Ks3YeOc8epT3KDFFfbrhWphB6852fKDGjd8jrg43qbi-gWoPqMvl85QJgJdca_G7d66HgjFZifl4KEVoVWfwVbVDxSvOwJqxV31gtiZaxf7oaMtVLjiGpiF-7VGN-oZbBrZej82bHxzIIB_7mtCBrIV1axrUyr-kToNQPPgcKcYqg

At the sandbox environment, you will have to put the number +44 7258777150 and 0000 for the password, then accept the authorization and then redirects you to the redirect page you defined. ( you must have defined in the development revolut account, in the jwt, and in the url)



5. retrieve_all_accounts

Retrieve all accounts from the Revolut Open Banking API.

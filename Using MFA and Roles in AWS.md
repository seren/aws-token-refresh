# Using MFA and Roles in AWS


**TL/DR:** For security, users have a set of permanent credentials that require MFA and can do nothing but request temporary (session) credentials. Using these temporary MFA-enabled tokens, they are allowed perform some actions and to assume roles in the main or other accounts. These assumed roles are what grant the final set of permissions the users need to perform their duties (including full administration).

The following examples show how to retrieve and use temporary session credentials, and how to retrieve and use role (cross-account in our example) session credentials, with and without MFA. The examples use shell code, but the concepts hold true for other languages.


## Using session credentials with MFA (no role assumption)

Our user accounts have policies applied which restrict the actions that can be performed without MFA.

~~~bash
# This will fail:

export AWS_ACCESS_KEY_ID="AKIAJFFBSWF5EXAMPLE"
export AWS_SECRET_ACCESS_KEY="LcUFzdfyTzNAo+vuuHBxUpGwrNTJrrEXAMPLEKEY"

aws --region us-east-1 ec2 describe-instances

An error occurred (UnauthorizedOperation) when calling the DescribeInstances operation: You are not authorized to perform this operation.
~~~

You can use normal credentials, with an mfa token, to get temporary session credentials. These have the MFA attribute set, so the policy will allow additional API calls that would otherwise be denied.

First, get the temporary session credentials:

~~~bash
MFA_TOKEN=$(mfa aws-myorg-users-jones -q)
MFA_DEVICE="arn:aws:iam::694237938522:mfa/jones"

# Get session credentials from STS
JSON=$(aws sts get-session-token --serial-number ${MFA_DEVICE} --token-code ${MFA_TOKEN})

echo $JSON
{
    "Credentials": {
        "SecretAccessKey": "GG+xvoLF0HKCV8DGhk1lQCss6eu4vEXAMPLEKEY",
        "SessionToken": "FQoDeXdzEBw...<remainder of security token>",
        "Expiration": "2017-11-23T06:36:57Z",
        "AccessKeyId": "ASIAIGMQ2ZKW4EXAMPLE"
    }
}

# Export the new session credentials
export AWS_ACCESS_KEY_ID=`echo ${JSON} | jq '.Credentials.AccessKeyId' | tr -d '"'`
export AWS_SECRET_ACCESS_KEY=`echo ${JSON} | jq '.Credentials.SecretAccessKey' | tr -d '"'`
export AWS_SESSION_TOKEN=`echo ${JSON} | jq '.Credentials.SessionToken' | tr -d '"'`

~~~

Then use the temporary session credentials to make the API calls:

~~~bash
# With the new session credentials, this will succeed:
aws --region us-east-1 ec2 describe-instances

{
    "Reservations": [
        {
            "Instances": [
                {
...
~~~


Note: There are three components to session credentials:

~~~bash
$ export AWS_ACCESS_KEY_ID=AKIAI44QH8DHBEXAMPLE
$ export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
$ export AWS_SESSION_TOKEN=AQoDYXdzEJr...<remainder of security token>
~~~


## Assuming roles (cross-account or not)

There are two ways to assume a role, depending on the account restrictions:

1. If MFA is required for the regular IAM credentials to call `sts assume-role`: `aws sts assume-role --role-arn ${ROLE_ARN} --role-session-name "${LOGNAME}-${DATESTAMP}" --serial-number ${MFA_DEVICE} --token-code ${MFA_TOKEN}`
1. If the regular IAM credentials can call `sts assume-role` without MFA: `aws sts assume-role --role-arn ${ROLE_ARN} --role-session-name "${LOGNAME}-${DATESTAMP}"`

If you are already using session credentials that were obtained using MFA, you can use the second option since the MFA attribute will carry over (you don't have to use MFA a second time).

~~~bash
# Assuming our current environment credentials (eg. AWS_*) are allowed to call assume-role
ROLE_ARN="arn:aws:iam::303064072661:role/myorg_admin"
DATESTAMP=$(date +"%Y-%m-%d-%H-%M-%S")

JSON=$(aws sts assume-role --role-arn ${ROLE_ARN} --role-session-name "${LOGNAME}-${DATESTAMP}")

echo $JSON
{
    "AssumedRoleUser": {
        "AssumedRoleId": "AROAJ2O5CEKIUVIUOXXXX:jones-2017-11-22-14-47-09",
        "Arn": "arn:aws:sts::303064072661:assumed-role/myorg_admin/jones-2017-11-22-14-47-09"
    },
    "Credentials": {
        "SecretAccessKey": "JeXc31hsWEvT47JDR7HtHBjkiBjsvEXAMPLEKEY",
        "SessionToken": "FQoDYXdzECAaD...<remainder of security token>",
        "Expiration": "2017-11-22T23:47:26Z",
        "AccessKeyId": "ASIAJJR44GIKEXAMPLE"
    }
}

# Export the session credentials for the role
export AWS_ACCESS_KEY_ID=`echo ${JSON} | jq '.Credentials.AccessKeyId' | tr -d '"'`
export AWS_SECRET_ACCESS_KEY=`echo ${JSON} | jq '.Credentials.SecretAccessKey' | tr -d '"'`
export AWS_SESSION_TOKEN=`echo ${JSON} | jq '.Credentials.SessionToken' | tr -d '"'`

~~~

*Author: Seren Thompson*

*Edition: 2018-10-17*
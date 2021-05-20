## Overview

This script retrieves temporary IAM user credentials (with MFA) or role credentials from AWS STS, and generates or updates standard `credentials` and `config` files for use with AWS CLI, Boto, or anything else that uses AWS profiles.



## Requirements

- Bash
- AWS CLI tools (to make STS calls)
  - https://docs.aws.amazon.com/cli/latest/userguide/installing.html
- An MFA (multi-factor authentication) token generator such as:
  - [Google Authenticator](https://www.google.com/search?q=google+authenticator)
  - [Authy](https://authy.com/download/)
  - Something else (there are [many options](https://www.google.com/search?q=2-factor+authentication+download) including CLI-based tools. Keywords to search for include: TOTP, MFA, and 2FA)



## Usage
- To get credentials: `token <profilename>`
- To export credentials into environment variables: `awsenv <profilename>`



## Getting started

**Warning:** The `config` file is recreated each time. Any customizations should be done in the `credentials` file or the profile files.

### File and shell changes

Run the `setup.sh` script or perform the following four steps manually:

1. Clone the git repo into a local directory (we'll be using `~/aws-token-refresh` in these examples):

  ~~~
  git clone https://github.com/seren/aws-token-refresh.git ~/aws-token-refresh
  ~~~

2. Create a directory for credentials (most tools expect them to be in `~/.aws`). Create a `aws-profiles` directory within:
	
  ~~~
  mkdir -p ${HOME}/.aws/aws-profiles
  chmod 700 ${HOME}/.aws/aws-profiles
  ~~~

3. In `profile-additions.sh`, update the `AWS_SCRIPTS_DIR` value file to the directory containing the scripts (ex. `${HOME}/aws-token-refresh`).
	
4. In your shell's login profile (usually `.bash_profile`, if you use bash), source `profile-additions.source_me`:
	
  ~~~
  echo 'source "${HOME}/aws-token-refresh/profile-additions.source_me"' >> ${HOME}/.profile
  ~~~


### Create the IAM profiles

Create profile files in `~/.aws/aws-profiles/`. These files are what are used to generate the `credentials` file (for the aws cli tools) and `config` file (formated slightly differently for boto). They should have at least the following information:

  Note: You can also create profiles for non-IAM accounts or accounts that don't use MFA. They'll be added to the `credentials` and `config` files.

  - **For an IAM user profile:**

    ~~~
    [mainuser]
    # An optional comment. Blah
    aws_access_key_id = AKIAJHEGCHEXAMPLE
    aws_secret_access_key = fSU2a3BdmxVX5cX0+HFw6IBcNaEXAMPLEKEY
    mfa_id = arn:aws:iam::12342567890:mfa/mainuser
    account_id = 12342567890
    region = us-east-1
    mfa_type = virtual
    ~~~
  
    - `[profilename]` - The nickname you want to give this profile. It needs to match the filename.
    - `# Blah` - You may place comment lines within the profile
    - `aws_access_key_id` - Key for IAM user (starts with `AKAI`)
    - `aws_secret_access_key` - Key secret for IAM user
    - `mfa_id` - The ARN of the virtual MFA device from the IAM user credentials page
    - `account_id` - Optional, but useful to avoid confusion when using multiple profile files
    - `region` - Optional. Useful if you always use the same region, or want to use different nicknames for different regions
    - `mfa_type` - Optional. If not specified, user is prompted for the MFA token. Possible values:
      - `virtual` (an MFA-generating app, specified as `MFA_PROGRAM` in `aws-token-or-role-refresh.sh`)
      - `yubikey` (hardware token) 

  - **For an IAM role profile:**

    ~~~
    [profilename]
    # An optional comment. Blah
    role_name = myadminrole
    account_id = 12342567890
    master_profile = mainuser
    region = us-east-1
    ~~~

    - `[profilename]` - The nickname you want to give this profile. It needs to match the filename.
    - `# Blah` - You may place comment lines within the profile
    - `role_name` - The name of the IAM role to assume. NOTE: The presence of this is also used to determine whether a profile is a "user" profile or a "role" profile.
    - `account_id` - The account ID that the role is in. Used, along with the `role_name`, to form the role ARN
    - `master_profile` - The name of the user profile which has permissions to assume this role.
    - `region` - Optional. Useful if you always use the same region, or want to use different nicknames for different regions



## Notes

- The script only modifies individual profile sections of the `credentials` file, so you can add extra profiles to the `credentials` file manually without them being overwritten.

- The `config` file is recreated from the `credentials` file during each run, so any customization should be done in the `credentials` file.

- The `[profilename]` must match the profile filename, but doesn't need to match the IAM role name.



## AWS Web Console Tips

If you've just started using roles, the AWS Web Console has a nice feature where you can switch between them. It can remember up to 5 recently switched-to roles. To add a role, choose the `Switch Role` option in the user menu in the upper-right menu bar of the web console page, or enter a url like so:

[https://signin.aws.amazon.com/switchrole?account=1234567890&roleName=myadminrole&displayName=account1-admin](https://signin.aws.amazon.com/switchrole?account=1234567890&roleName=myadminrole&displayName=account1-admin)

For more than 5 roles, you may want to check out browser extensions/add-ons such as [aws-extend-switch-roles](https://github.com/tilfin/aws-extend-switch-roles)


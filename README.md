## Overview

These scripts retrieve temporary IAM user credentials (with MFA) or role credentials from AWS STS, and generate standard `credentials` and `config` files for use with AWS CLI, Boto, or anything else that uses AWS profiles.

## Requirements

- AWS CLI tools (to make STS calls)
- Bash
- An MFA (multi-factor authentication) token generator such as:
	- [Google Authenticator](https://www.google.com/search?q=google+authenticator)
	- [Authy](https://authy.com/download/)
	- Something else (there are [many options](https://www.google.com/search?q=2-factor+authentication+download))


## Usage:
- Get credentials: `token <profilename>`
- Export credentials into environment variables: `awsenv <profilename>`


## Getting started:

1. Clone the git repo into a local directory (we'll be using `~/aws-scripts` in these examples):

	~~~
	git clone https://github.com/seren/aws-token-refresh.git ~/aws-scripts
	~~~

2. Create a directory for credentials (most tools expect them to be in `~/.aws`). Create a `aws-profiles` directory within:

	~~~
	mkdir -p ${HOME}/.aws/aws-profiles
	chmod 700 ${HOME}/.aws/aws-profiles
	~~~

3. In `profile-additions.sh`, update the `AWS_SCRIPTS_DIR` value file to the directory containing the scripts (ex. `${HOME}/aws-scripts`).

4. In your shell's profile (ex. `.profile` or `.bashrc`), source `profile-additions.sh`:

	~~~
	echo 'source "~/aws-scripts/profile-additions.sh"' >> ${HOME}/.profile
	~~~

5. Create profile files in `~/.aws/aws-profiles/`. These files are what are used to generate the `credentials` file (for the aws cli tools) and `config` file (formated slightly differently for boto). They should have at least the following information:

	- **For an IAM user profile:**

		~~~
		[mainuser]
		# An optional comment
		aws_access_key_id = AKIAJHEGCHEXAMPLE
		aws_secret_access_key = fSU2a3BdmxVX5cX0+HFw6IBcNaEXAMPLEKEY
		mfa_id = arn:aws:iam::12342567890:mfa/mainuser
		account_id = 1234256789
		region = us-east-1
		~~~
	
		- `[profilename]` - The nickname you want to give this profile. It needs to match the filename.
		- `# Blah` - You may place comment lines within the profile
		- `region` - Optional. Useful if you always use the same region, or want to use different nicknames for different regions
		- `aws_access_key_id` and `aws_secret_access_key` - Normal IAM credentials
		- `mfa_id` - The ARN of the virtual MFA device used to generate MFA tokens
		- `account_id` - Needed for adminpy


	- **For an IAM role profile:**

		~~~
		[profilename]
		# Blah
		role_name = myadminrole
		account_id = 1234256789
		master_profile = mainuser
		region = us-east-1
		~~~

		- `[profilename]` - The nickname you want to give this profile. It needs to match the filename.
		- `# Blah` - You may place comment lines within the profile
		- `role_name` - The name of the role to assume. NOTE: The presence of this is also used to determine whether a profile is a "user" profile or a "role" profile.
		- `account_id` - The account ID that the role is in. Used, along with the role_name, to form the role ARN
		- `master_profile` - Optional. The name of the profile to use to assume this role. Can be used to override the default `MASTER_PROFILE` setting in the `aws-token-or-role-refresh.sh` script.
		- `region` - Optional. Useful if you always use the same region, or want to use different nicknames for different regions

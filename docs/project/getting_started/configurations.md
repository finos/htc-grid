# Configuring Local Environment

## AWS CLI

Configure the AWS CLI to use your AWS account: see https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html

Check connectivity as follows:

```bash
$ aws sts get-caller-identity
{
    "Account": "XXXXXXXXXXXX",
    "UserId": "XXXXXXXXXXXXXXXXXXXXX",
    "Arn": "arn:aws:iam::XXXXXXXXXXXX:user/XXXXXXX"
}
```

## Python

The current release of HTC requires python3.7, and the documentation assumes the use of *virtualenv*. Set this up as follows:

```bash
$ cd <project_root>/
$ virtualenv --python=$PATH/python3.7 venv
created virtual environment CPython3.7.10.final.0-64 in 1329ms
  creator CPython3Posix(dest=<project_roor>/venv, clear=False, no_vcs_ignore=False, global=False)
  seeder FromAppData(download=False, pip=bundle, setuptools=bundle, wheel=bundle, via=copy, app_data_dir=/Users/user/Library/Application Support/virtualenv)
    added seed packages: pip==21.0.1, setuptools==54.1.2, wheel==0.36.2
  activators BashActivator,CShellActivator,FishActivator,PowerShellActivator,PythonActivator,XonshActivator

```

Check you have the correct version of python (`3.7.x`), with a path rooted on `<project_root>`, then start the environment:

```
$  source ./venv/bin/activate
(venv) 8c8590cffb8f:htc-grid-0.0.1 $
```

Check the python version as follows:

```bash
$ which python
<project_root>/venv/bin/python
$ python -V
Python 3.7.10
```

For further details on *virtualenv* see https://sourabhbajaj.com/mac-setup/Python/virtualenv.html
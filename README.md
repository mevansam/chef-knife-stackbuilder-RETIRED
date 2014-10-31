# Knife StackBuilder plugin

## Usage

```
knife stack initialize repo

  Initializes or validates an existing stack repo. The stack repo should contain the 
  following folders along with a Berksfile.
  
  * environments
  * stacks
  * secrets
  * databags
  * cookbooks
  * roles

  --path

    Path to create and initialize the stack chef repository. If the repository already 
    exists then any it will be validated. If the provided path begins with git:, http: 
    or https:, it will be assumed to be a git repo. A branch/label may be specified
    by preceding it with a : after the path.
    
    i.e. http://github.com/mevansam/mystack:tag1

  --cert_path | --certs

    If "--cert_path" is specified then it should point to a directory with a folder for 
    each server domain name containing that server's certificate files. 
    
    If instead "--certs" are specified then it should provide a comma separated list of
    server domain names for which self-signed certificates will be generated.

  --envs
    
    Comma separated list of environments to generate along with encryption keys for each.
```

```
knife stack upload cookbook[s]
```

```
knife stack upload environment[s]
```

```
knife stack upload role[s]
```

```
knife stack upload data bag[s]
```

```
knife stack upload repo
```

```
knife stack build
```

## Contributing

1. Fork the repository on Github
2. Write your change
3. Write tests for your change (if applicable)
4. Run the tests, ensuring they all pass
5. Submit a Pull Request

## License and Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Author: Mevan Samaratunga (mevansam@gmail.com)

# Knife Conductor plugin

TODO: ...

## Usage

```
knife initialize stack repo

    --path

      Path to create and initialize the stack chef repository. If the repository already exists then any it will be validated.

    --cert_path | --certs

      If "--cert_path" is provided then it should point to a directory with a folder for each server domain name containing the server cert files. If instead "--certs" are provided then

    --
```

```
knife upload stack cookbook[s]
```

```
knife upload stack environment[s]
```

```
knife upload stack role[s]
```

```
knife upload stack data bag[s]
```

```
knife sync stack
```

## Design

TODO: ...

## Extending

TODO: ...

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

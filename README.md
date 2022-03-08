# Semantic Config Validation

For many systems, it is not sufficient to check the syntax of a configuration, instead we want to start up some kind of system with it and 
confirm that this system is happy with the configuration. 

This action does just this! It:
1. Starts up a database (neo4j)
2. Takes a directory containing independent configurations
3. Splits configurations into groups of `n`
4. In parallel, validates them by:
    1. Starting up a system capable of validating the configuration
    2. Feeds the configuration to that system
    3. Curls some endpoint
    4. Checks if the the response is expected. If it is not expected, we fail.

## Inputs

| Variable | Description | default | required |
| ----------- | ----------- | ------- | ----- |
| config-units: |  Directory containing the configuration units to check | conf-files/backend | false
| config-tester-success-result: |  Result associated with success from a config-tester | {"databaseConnection":{"Right":{"value":"ok"}}} | false
| config-tester-health-endpoint: |  Which endpoint to hit to determine success/failure. | localhost:9000/health | false
| config-tester-startup-args: |  All arguments required to give to a config-tester for it to start up properly. | 0.12.0 6912 | false
| config-tester-response-ready: |  Token from endpoint indicating startup | ^{ | false
| validator-image: |  Image to run validations against | | true  | validation-script: |  Script which validates configuration unit when it run inside of a validator | ./defaults/testing-resources/test-backend-config.sh | false
| neo4j-docker-compose: |  docker-compose for neo4j | defaults/docker-resources/docker-compose.yml | false
| neo4j-credentials: |  Credentials for authenticating with neo4j | | true  | template-docker-compose: |  Template describing how to build each individual configuration unit | defaults/docker-resources/docker-compose-template.yml | false
| num-parallel-checks: |  Number of config units to test concurrently | 3 | false
| problem-matchers: |  Directory containing all github problem matchers to use. Defaults to a path useful to GarnerCorp | defaults/problem-matchers | false

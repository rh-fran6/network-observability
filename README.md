# Loki Installation Script

## Summary

The Loki Installation Script automates the deployment and configuration of Loki, a powerful log aggregation system, on an OpenShift cluster. It simplifies the setup process by handling the creation of IAM roles, policies, S3 buckets, and other necessary resources required for deploying Loki and network observability components.

## Prerequisites

Before running the script, ensure the following prerequisites are met:
- Access to an OpenShift cluster
- AWS CLI installed and configured with appropriate permissions
- `oc` (OpenShift CLI) installed and configured
- `aws` (AWS CLI) installed and configured
- Administrative access to the OpenShift cluster

## Usage

Follow these steps to deploy Loki on your OpenShift cluster:

1. **Clone the Repository**:
    ```bash
    git clone https://github.com/rh-fran6/network-observability.git
    cd network-observability
    ```

    Update the variables in the main script with your chosen values.

2. **Run the Script**:
    Execute the Bash script on your local machine:
    ```bash
    ./install.sh
    ```

3. **Cleanup**: To cleanup, do the followng:
     Execute the Bash script on your local machine:
    ```bash
    ./cleanup.sh
    ```

## Error Handling

The script includes error handling mechanisms to address potential issues during the deployment process. Any encountered errors, such as file handling errors or manifest conversion problems, will be displayed on the console.

## Contributing

We welcome contributions to this project. If you have any improvements or feature suggestions, please feel free to raise a pull request on GitHub.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact

If you have any questions, suggestions, or feedback, please feel free to reach out by opening an issue on the [GitHub repository](https://github.com/your-organization/loki-installation/issues).

Happy logging with Loki!

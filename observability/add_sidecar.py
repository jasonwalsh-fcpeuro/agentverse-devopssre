import yaml
import sys
import os

# --- Configuration ---
INPUT_FILE = 'vllm-cloudrun.yaml'
OUTPUT_FILE = 'service.yaml'
MAIN_APP_NAME = 'app' # The new required name for the main application container
GMP_SIDECAR_NAME = 'collector'
GMP_SECRET_NAME = 'vllm-monitor-config' # The secret that holds the GMP config.yaml

def main():
    """
    Reads a Cloud Run service YAML, replaces any existing monitoring sidecar
    with the new managed GMP sidecar, and writes a clean configuration file.
    """
    # 1. Get environment variables
    try:
        project_id = os.environ['PROJECT_ID']
    except KeyError as e:
        print(f"ERROR: Environment variable {e} is not set.", file=sys.stderr)
        sys.exit(1)

    # 2. Define the new YAML sections based on the managed GMP sidecar pattern
    gmp_sidecar_container = {
        'name': GMP_SIDECAR_NAME,
        'image': 'us-docker.pkg.dev/cloud-ops-agents-artifacts/cloud-run-gmp-sidecar/cloud-run-gmp-sidecar:1.2.0',
        'volumeMounts': [{'name': 'config', 'mountPath': '/etc/rungmp/'}]
    }

    gmp_volume = {
        'name': 'config',
        'secret': {
            'secretName': GMP_SECRET_NAME,
            'items': [{'key': 'latest', 'path': 'config.yaml'}]
        }
    }

    dependency_annotation = f'{{"{GMP_SIDECAR_NAME}":["{MAIN_APP_NAME}"]}}'
    secret_annotation = f'{GMP_SECRET_NAME}:projects/{project_id}/secrets/{GMP_SECRET_NAME}'

    # 3. Read the source YAML file
    try:
        with open(INPUT_FILE, 'r') as f:
            service_data = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"ERROR: Input file '{INPUT_FILE}' not found. Please run 'gcloud run services describe' first.", file=sys.stderr)
        sys.exit(1)

    # 4. Safely modify the YAML data structure
    spec_template = service_data['spec']['template']
    
    # a. Find and rename the main application container to 'app'
    spec_template['spec']['containers'][0]['name'] = MAIN_APP_NAME
    print(f"✅ Renamed main container to '{MAIN_APP_NAME}'.")

    # b. Filter out any old collector container and its volume
    spec_template['spec']['containers'] = [
        c for c in spec_template['spec']['containers'] if c.get('name') != GMP_SIDECAR_NAME
    ]
    if 'volumes' in spec_template['spec']:
        spec_template['spec']['volumes'] = [
            v for v in spec_template['spec']['volumes'] if v.get('name') != 'prom-config'
        ]
    print("✅ Removed old sidecar container and volume definitions.")

    # c. Add the new GMP sidecar container
    spec_template['spec']['containers'].append(gmp_sidecar_container)
    print("✅ Added new managed GMP sidecar container.")

    # d. Add the new config volume for the GMP sidecar
    if 'volumes' not in spec_template['spec']:
        spec_template['spec']['volumes'] = []
    spec_template['spec']['volumes'].append(gmp_volume)
    print("✅ Added new config volume for GMP sidecar.")

    # e. Set the correct annotations
    spec_template['metadata']['annotations']['run.googleapis.com/container-dependencies'] = dependency_annotation
    spec_template['metadata']['annotations']['run.googleapis.com/secrets'] = secret_annotation
    print("✅ Set correct dependency and secret annotations.")
    
    # 5. --- THIS SECTION REMOVES SERVER-GENERATED FIELDS ---
    # a. Remove the 'status' block entirely, as requested.
    if 'status' in service_data:
        del service_data['status']
        print("✅ Removed server-generated 'status' block.")

    # b. Remove other server-generated metadata for a clean file.
    for key in list(service_data['metadata']):
      if key not in ['name', 'labels', 'annotations']:
        del service_data['metadata'][key]
    if 'metadata' in service_data['spec']['template'] and 'labels' in service_data['spec']['template']['metadata']:
      del service_data['spec']['template']['metadata']['labels']
    print("✅ Cleaned other server-generated metadata fields.")


    # 6. Write the new, correct YAML file
    try:
        with open(OUTPUT_FILE, 'w') as f:
            yaml.dump(service_data, f, sort_keys=False, indent=2, Dumper=yaml.Dumper)
        print(f"✅ Successfully created clean '{OUTPUT_FILE}' with the correct GMP sidecar configuration.")
    except Exception as e:
        print(f"An error occurred while writing the file: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    try:
        import yaml
    except ImportError:
        print("PyYAML library not found. Please install it by running: pip install pyyaml", file=sys.stderr)
        sys.exit(1)
    main()

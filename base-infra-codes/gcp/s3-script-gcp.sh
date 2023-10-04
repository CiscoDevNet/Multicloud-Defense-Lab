#!/bin/bash

# Define your variables
POD_NUMBER=1
TF_STATE_BUCKET="mcd-state-files-do-not-delete"
TF_STATE_KEY="gcp-$POD_NUMBER-terraform.tfstate" 
AWS_REGION="us-east-1"  


function upload_state() {
    # Run `terraform state pull` to retrieve the current state
    terraform state pull > current_state.json
    if [ $? -ne 0 ]; then
    echo "Error pulling state file"
    exit 1
    fi

    # Upload the state file to S3
    aws s3 cp current_state.json "s3://${TF_STATE_BUCKET}/${TF_STATE_KEY}" --region "${AWS_REGION}"
    if [ $? -ne 0 ]; then
    echo "Error uploading state file to S3"
    exit 1
    fi

    echo "Terraform state has been pulled and saved to S3 bucket: s3://${TF_STATE_BUCKET}/${TF_STATE_KEY}"
}

function import_state() {
    # Import the state file from S3
    aws s3 cp "s3://${TF_STATE_BUCKET}/${TF_STATE_KEY}" current_state.json --region "${AWS_REGION}"
    if [ $? -ne 0 ]; then
    echo "Error downloading state file from S3"
    exit 1
    fi

    # Run `terraform state push` to import the state
    terraform state push current_state.json
    if [ $? -ne 0 ]; then
    echo "Error importing state file"
    exit 1
    fi

    echo "Terraform state has been imported from S3 bucket: s3://${TF_STATE_BUCKET}/${TF_STATE_KEY}"
}

# Run the function based on the first argument
case $1 in
    upload)
        upload_state
        ;;
    import)
        import_state
        ;;
    *)
        echo "Usage: $0 {upload|import}"
        exit 1
esac

# rm current_state.json

#!/bin/bash
# Script to build, package, and deploy AWS Lambda Telemetry Backend

set -e

echo "=== Packaging AWS Lambda Function & Dependencies ==="
PACKAGE_DIR="package"
rm -rf "$PACKAGE_DIR" deployment_package.zip

mkdir -p "$PACKAGE_DIR"
pip install --target "$PACKAGE_DIR" psycopg2-binary nlohmann-json --quiet || pip install --target "$PACKAGE_DIR" psycopg2-binary --quiet

cp lambda_function.py "$PACKAGE_DIR/"
cd "$PACKAGE_DIR"
zip -r ../deployment_package.zip . > /dev/null
cd ..

echo "=== Package deployment_package.zip ready ==="
echo "To deploy via AWS SAM CLI:"
echo "  sam build"
echo "  sam deploy --guided"
echo ""
echo "To deploy manually via AWS CLI:"
echo "  aws lambda create-function --function-name TelemetryIngestFunc \\"
echo "      --runtime python3.12 --role arn:aws:iam::ACCOUNT_ID:role/service-role/LambdaRole \\"
echo "      --handler lambda_function.lambda_handler --zip-file fileb://deployment_package.zip"

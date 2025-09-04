import  os
import boto3
import json
import logging

s3 = boto3.client('s3')

def lambda_handler(event, context):
    bucket = os.environ.get('BUCKET_NAME')
    if not bucket:
        return {"statusCode": 500, "body": json.dumps({"error": "BUCKET_NAME environment variable not set"})}
    
    try:
        resp = s3.list_objects_v2(Bucket=bucket)
        contents = []
        for obj in resp.get('Contents', []):
            contents.append({
                'Key': obj['Key'],
                'LastModified': obj['LastModified'].isoformat(),
                'Size': obj['Size'],
                'StorageClass': obj['StorageClass']
            })
        return {"statusCode": 200, "body": json.dumps(contents)}
    
    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
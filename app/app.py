from flask import Flask, jsonify, request
import os
import boto3
from datetime import datetime
import logging

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# S3 client
s3_client = None
bucket_name = os.environ.get('S3_BUCKET_NAME')

if bucket_name:
    try:
        s3_client = boto3.client('s3')
        logger.info(f"S3 client initialized for bucket: {bucket_name}")
    except Exception as e:
        logger.error(f"Failed to initialize S3 client: {e}")


@app.route('/')
def home():
    """Home endpoint"""
    return jsonify({
        'message': 'Flask application deployed successfully!',
        'timestamp': datetime.utcnow().isoformat(),
        'status': 'healthy'
    })


@app.route('/health')
def health():
    """Health check endpoint"""
    health_status = {
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'checks': {
            's3_configured': bucket_name is not None,
        }
    }
    
    # Test S3 connectivity
    if s3_client and bucket_name:
        try:
            s3_client.head_bucket(Bucket=bucket_name)
            health_status['checks']['s3_accessible'] = True
        except Exception as e:
            health_status['checks']['s3_accessible'] = False
            health_status['checks']['s3_error'] = str(e)
    
    status_code = 200 if health_status['status'] == 'healthy' else 503
    return jsonify(health_status), status_code


@app.route('/api/data', methods=['GET', 'POST'])
def data():
    """Data endpoint with S3 integration"""
    if request.method == 'GET':
        return jsonify({
            'message': 'Data endpoint',
            'method': 'GET',
            'timestamp': datetime.utcnow().isoformat()
        })
    
    elif request.method == 'POST':
        data = request.get_json()
        
        # Store in S3 if configured
        if s3_client and bucket_name:
            try:
                key = f"data/{datetime.utcnow().isoformat()}.json"
                s3_client.put_object(
                    Bucket=bucket_name,
                    Key=key,
                    Body=str(data),
                    ContentType='application/json'
                )
                return jsonify({
                    'message': 'Data stored successfully',
                    's3_key': key,
                    'timestamp': datetime.utcnow().isoformat()
                }), 201
            except Exception as e:
                logger.error(f"Failed to store data in S3: {e}")
                return jsonify({
                    'error': 'Failed to store data',
                    'details': str(e)
                }), 500
        else:
            return jsonify({
                'message': 'Data received (S3 not configured)',
                'data': data,
                'timestamp': datetime.utcnow().isoformat()
            }), 201


@app.route('/api/info')
def info():
    """Application info endpoint"""
    return jsonify({
        'application': 'Flask EC2 Deployment',
        'version': '1.0.0',
        'environment': os.environ.get('ENVIRONMENT', 'development'),
        'python_version': os.sys.version,
        'timestamp': datetime.utcnow().isoformat()
    })


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)

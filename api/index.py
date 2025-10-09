import sys
import os
from pathlib import Path
import json

# Add the parent directory to sys.path so we can import from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def handler(request):
    """Simple Vercel serverless function handler"""
    try:
        # Import here to avoid cold start issues
        from app.main import app
        from mangum import Adapter
        
        # Create ASGI adapter
        asgi_handler = Adapter(app)
        return asgi_handler(request)
        
    except Exception as e:
        # Fallback response for debugging
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps({
                'ok': False,
                'error': str(e),
                'path': request.get('path', 'unknown'),
                'method': request.get('httpMethod', 'unknown')
            })
        }
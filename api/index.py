import sys
import os
from pathlib import Path

# Add the parent directory to sys.path so we can import from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Import the FastAPI app
try:
    from app.main import app
    
    # For Vercel, we need to use the ASGI handler
    from mangum import Adapter
    handler = Adapter(app)
except ImportError as e:
    print(f"Import error: {e}")
    # Fallback basic handler
    from http.server import BaseHTTPRequestHandler
    import json
    
    class handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/api/health':
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({"ok": True, "error": f"Import failed: {e}"}).encode())
            else:
                self.send_response(404)
                self.end_headers()
        
        def do_POST(self):
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({"message": "API endpoint", "error": f"Import failed: {e}"}).encode())
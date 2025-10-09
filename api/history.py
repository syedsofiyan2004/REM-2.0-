from http.server import BaseHTTPRequestHandler
import json
import sys
import os

# Add the parent directory to sys.path so we can import from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            from app.main import get_msgs
            
            # Parse query parameters for session_id
            from urllib.parse import urlparse, parse_qs
            parsed_url = urlparse(self.path)
            query_params = parse_qs(parsed_url.query)
            session_id = query_params.get('session_id', ['local'])[0]
            
            # Get chat history
            messages = get_msgs(session_id)
            
            # Format for frontend
            chat_history = []
            for msg in messages:
                role = msg.get('role', '')
                content = msg.get('content', [])
                if content and isinstance(content, list) and len(content) > 0:
                    text = content[0].get('text', '') if isinstance(content[0], dict) else str(content[0])
                    chat_history.append({
                        'role': role,
                        'text': text
                    })
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({'history': chat_history}).encode())
            
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e), 'history': []}).encode())
    
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
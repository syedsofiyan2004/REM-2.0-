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
            
            # Format for frontend - return direct array, not wrapped object
            chat_history = []
            for msg in messages:
                role = msg.get('role', '')
                content = msg.get('content', [])
                if content and isinstance(content, list) and len(content) > 0:
                    # Extract text from the bedrock format
                    text_content = content[0]
                    if isinstance(text_content, dict):
                        text = text_content.get('text', '')
                    else:
                        text = str(text_content)
                    
                    if text.strip():  # Only add non-empty messages
                        chat_history.append({
                            'role': role,
                            'content': text  # Frontend expects 'content', not 'text'
                        })

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            # Return direct array, not wrapped in object
            self.wfile.write(json.dumps(chat_history).encode())
            
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
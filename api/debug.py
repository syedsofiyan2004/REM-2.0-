from http.server import BaseHTTPRequestHandler
import json
import sys
import os

# Add the parent directory to sys.path so we can import from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            from app.utils import add_turn, get_msgs, _history
            
            # Add a test conversation
            session_id = "test"
            add_turn(session_id, "user", "Hello, how are you?")
            add_turn(session_id, "assistant", "I'm doing great! Thanks for asking.")
            
            # Get the messages back
            messages = get_msgs(session_id)
            
            # Also show raw history
            raw_history = dict(_history)
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            response = {
                'status': 'success',
                'raw_history_keys': list(raw_history.keys()),
                'test_session_raw': list(raw_history.get('test', [])),
                'formatted_messages': messages,
                'message_count': len(messages)
            }
            
            self.wfile.write(json.dumps(response, indent=2).encode())
            
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())
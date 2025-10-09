from http.server import BaseHTTPRequestHandler
import json
import sys
import os
from datetime import datetime

# Add the parent directory to sys.path so we can import from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

class handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            # Import the full AI functionality
            from app.main import bedrock_reply, _compose_system, PERSONA_BLESSED_BOY, enforce_identity, add_turn, get_msgs
            
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            text = data.get('text', '').strip()
            session_id = data.get('session_id', 'local').strip()
            style = data.get('style')  # This gets the personality mode
            
            if not text:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({'error': 'Empty text'}).encode())
                return
            
            # Handle special built-in queries
            q = text.lower()
            if "date" in q and "update" not in q:
                reply = datetime.now().strftime("Today is %B %d, %Y.")
            elif "time" in q:
                reply = datetime.now().strftime("It's %I:%M %p.")
            elif q in {"what's your name","whats your name","your name?","who are you"}:
                reply = "Rem."
            else:
                # Use full AI with personality styles and conversation history
                reply = bedrock_reply(_compose_system(PERSONA_BLESSED_BOY, style), session_id, text, style)
            
            # Clean the response and maintain identity
            final_reply = enforce_identity(reply)
            
            # Add to conversation history for context
            add_turn(session_id, "user", text)
            add_turn(session_id, "assistant", final_reply)
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({'reply': final_reply}).encode())
            
        except Exception as e:
            # Fallback response if AI fails
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            error_msg = f"I'm having technical difficulties right now. Error: {str(e)}"
            self.wfile.write(json.dumps({'reply': error_msg}).encode())
    
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    
    def do_GET(self):
        self.send_response(405)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps({'error': 'Method not allowed'}).encode())
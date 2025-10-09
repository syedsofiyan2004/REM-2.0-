from http.server import BaseHTTPRequestHandler
import json
import sys
import os

# Add the parent directory to sys.path so we can import from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

class handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            # Import TTS functions
            from app.main import polly_tts_with_visemes
            
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            text = data.get('text', '').strip()
            lang = data.get('lang')
            mode = data.get('mode')
            
            if not text:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps({'error': 'Provide text to speak'}).encode())
                return
            
            # Detect Hinglish (Hindi written in English letters) and common Hindi words
            hinglish_words = [
                'aap', 'aapka', 'aapki', 'haan', 'nahin', 'nahi', 'kya', 'kaise', 'kab', 'kahan', 
                'kyun', 'kaun', 'main', 'meri', 'mera', 'mujhe', 'tumhara', 'tumhari', 'tumhe',
                'woh', 'yeh', 'yah', 'iske', 'uske', 'iska', 'uska', 'bahut', 'accha', 'achha',
                'bura', 'theek', 'thik', 'samjha', 'samjhi', 'pata', 'malum', 'dekho', 'suno',
                'bol', 'bolo', 'kar', 'karo', 'mat', 'padh', 'padho', 'likh', 'likho', 'chal',
                'chalo', 'aa', 'aao', 'ja', 'jao', 'paani', 'pani', 'khana', 'ghar', 'kaam',
                'kitna', 'kitni', 'kuch', 'sab', 'sabhi', 'mere', 'tere', 'humara', 'tumhara',
                'bhi', 'toh', 'to', 'se', 'mein', 'pe', 'par', 'ke', 'ki', 'ka', 'hai', 'hain',
                'tha', 'thi', 'the', 'hoga', 'hogi', 'honge', 'dost', 'bhai', 'behen', 'mama',
                'papa', 'dada', 'dadi', 'nana', 'nani', 'beta', 'beti'
            ]
            
            # Check if text contains significant Hinglish words
            text_words = text.lower().split()
            hinglish_count = sum(1 for word in text_words if word in hinglish_words)
            hinglish_ratio = hinglish_count / len(text_words) if text_words else 0
            
            # If more than 20% of words are Hinglish, switch to Hindi TTS
            if hinglish_ratio > 0.2 and not lang:
                lang = 'hi-IN'  # Switch to Hindi TTS automatically
            
            # Generate speech
            audio_b64, marks = polly_tts_with_visemes(text, lang, mode)
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({
                'audio_b64': audio_b64,
                'marks': marks
            }).encode())
            
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())
    
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
from http.server import BaseHTTPRequestHandler
import json
import sys
import os
import traceback

# Add the parent directory to sys.path so we can import from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            # Test imports one by one
            import_results = {}
            
            # Test basic imports
            try:
                from app.main import PERSONA_BLESSED_BOY
                import_results['PERSONA_BLESSED_BOY'] = 'Success'
            except Exception as e:
                import_results['PERSONA_BLESSED_BOY'] = f'Error: {str(e)}'
            
            try:
                from app.main import bedrock_reply
                import_results['bedrock_reply'] = 'Success'
            except Exception as e:
                import_results['bedrock_reply'] = f'Error: {str(e)}'
            
            try:
                from app.main import get_msgs
                import_results['get_msgs'] = 'Success'
            except Exception as e:
                import_results['get_msgs'] = f'Error: {str(e)}'
            
            # Test persona_prompts directly
            try:
                from app.persona_prompts import PERSONA_BLESSED_BOY as PERSONA_TEST
                import_results['persona_prompts_direct'] = 'Success'
            except Exception as e:
                import_results['persona_prompts_direct'] = f'Error: {str(e)}'
            
            # Check file existence
            import_results['sys_path'] = sys.path[:3]  # First 3 paths
            import_results['current_dir'] = os.getcwd()
            import_results['file_exists_app_main'] = os.path.exists(os.path.join(os.getcwd(), 'app', 'main.py'))
            import_results['file_exists_app_persona'] = os.path.exists(os.path.join(os.getcwd(), 'app', 'persona_prompts.py'))
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(import_results, indent=2).encode())
            
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            error_info = {
                'error': str(e),
                'traceback': traceback.format_exc(),
                'cwd': os.getcwd()
            }
            self.wfile.write(json.dumps(error_info, indent=2).encode())
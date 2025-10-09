from http.server import BaseHTTPRequestHandler
import json
import sys
import os
import traceback

class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            diagnostic_info = {}
            
            # Basic Python environment
            diagnostic_info['python_version'] = sys.version
            diagnostic_info['working_directory'] = os.getcwd()
            diagnostic_info['python_path'] = sys.path[:5]  # First 5 paths
            
            # Environment variables (without sensitive data)
            env_vars = {}
            for key in os.environ:
                if any(secret in key.lower() for secret in ['key', 'secret', 'token', 'password']):
                    env_vars[key] = '[HIDDEN]'
                else:
                    env_vars[key] = os.environ[key]
            diagnostic_info['environment_variables'] = env_vars
            
            # File system check
            files_check = {}
            files_check['app_folder_exists'] = os.path.exists('app')
            files_check['app_utils_exists'] = os.path.exists('app/utils.py')
            files_check['app_main_exists'] = os.path.exists('app/main.py')
            files_check['app_persona_exists'] = os.path.exists('app/persona_prompts.py')
            
            if os.path.exists('app'):
                files_check['app_contents'] = os.listdir('app')
            
            diagnostic_info['file_system'] = files_check
            
            # Import tests (step by step)
            import_tests = {}
            
            # Test 1: Basic imports
            try:
                import boto3
                import_tests['boto3'] = 'Success'
            except Exception as e:
                import_tests['boto3'] = f'Failed: {str(e)}'
            
            try:
                from pydantic import BaseModel
                import_tests['pydantic'] = 'Success'
            except Exception as e:
                import_tests['pydantic'] = f'Failed: {str(e)}'
            
            # Test 2: App folder import
            try:
                sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
                import_tests['sys_path_modified'] = 'Success'
            except Exception as e:
                import_tests['sys_path_modified'] = f'Failed: {str(e)}'
            
            # Test 3: Utils import
            try:
                from app.utils import PERSONA_BLESSED_BOY
                import_tests['app_utils_persona'] = 'Success'
                import_tests['persona_content'] = PERSONA_BLESSED_BOY[:100] + '...'
            except Exception as e:
                import_tests['app_utils_persona'] = f'Failed: {str(e)}'
                import_tests['persona_traceback'] = traceback.format_exc()
            
            # Test 4: AWS client creation (without credentials)
            try:
                from app.utils import bedrock, polly
                import_tests['aws_clients'] = 'Success'
            except Exception as e:
                import_tests['aws_clients'] = f'Failed: {str(e)}'
                import_tests['aws_traceback'] = traceback.format_exc()
            
            diagnostic_info['imports'] = import_tests
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            self.wfile.write(json.dumps(diagnostic_info, indent=2, default=str).encode())
            
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            error_info = {
                'error': str(e),
                'traceback': traceback.format_exc(),
                'type': 'diagnostic_failure'
            }
            
            self.wfile.write(json.dumps(error_info, indent=2).encode())
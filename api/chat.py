import sys
import os
import json

# Add the parent directory to sys.path so we can import from app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def handler(request, context):
    """Chat endpoint"""
    
    # Handle CORS preflight
    if request.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': ''
        }
    
    try:
        # Import the actual chat function
        from app.main import bedrock_reply, _compose_system, PERSONA_BLESSED_BOY, enforce_identity, add_turn
        
        if request.get('httpMethod') != 'POST':
            return {
                'statusCode': 405,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Method not allowed'})
            }
        
        # Parse request body
        body = json.loads(request.get('body', '{}'))
        text = body.get('text', '').strip()
        session_id = body.get('session_id', 'local').strip()
        style = body.get('style')
        
        if not text:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Empty text'})
            }
        
        # Handle special queries
        import datetime
        q = text.lower()
        if "date" in q and "update" not in q:
            reply = datetime.datetime.now().strftime("Today is %B %d, %Y.")
        elif "time" in q:
            reply = datetime.datetime.now().strftime("It's %I:%M %p.")
        elif q in {"what's your name","whats your name","your name?","who are you"}:
            reply = "Rem."
        else:
            # Use bedrock for actual AI response
            reply = bedrock_reply(_compose_system(PERSONA_BLESSED_BOY, style), session_id, text, style)
        
        # Clean the response
        final_reply = enforce_identity(reply)
        
        # Add to conversation history
        add_turn(session_id, "user", text)
        add_turn(session_id, "assistant", final_reply)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'reply': final_reply})
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
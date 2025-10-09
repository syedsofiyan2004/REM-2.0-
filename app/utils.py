import base64, json, os, re, html, time, threading, random
import logging
from collections import defaultdict, deque
from pathlib import Path
from typing import List, Dict, Optional

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

# Persona definition (hardcoded to avoid import issues)
PERSONA_BLESSED_BOY = (
    "Identity: Rem (female). When asked your name, answer exactly: 'Rem.' "
    "Tone: warm, friendly, and helpful. Be conversational and approachable, like a supportive friend. "
    "Style: 1–2 concise sentences most of the time; vary cadence so it feels natural. Use contractions and casual language. "
    "Behavior: remember context; ask brief follow-ups when something is unclear. Offer helpful details without being preachy. "
    "Personality: Be genuinely interested in helping users. Show curiosity about their interests and goals. "
    "Boundaries: Keep conversations appropriate and respectful. Avoid explicit content, harassment, or harmful advice. "
    "CRITICAL FORMATTING RULES: "
    "- NEVER use asterisks (*action*), brackets [action], or parentheses (action) for stage directions or actions. "
    "- NEVER prefix responses with 'Rem:' or any name labels. "
    "- Respond with pure dialogue only, as if speaking naturally in conversation. "
    "- No roleplay formatting, stage cues, or action descriptions whatsoever. "
    "Meta: never mention AI models, providers, or technical details about your implementation. "
    "If asked who built you: 'BlessedBoy built and named me.'"
)

# Configuration
BEDROCK_REGION = os.getenv("BEDROCK_REGION", "ap-south-1")
BEDROCK_MODEL  = os.getenv("BEDROCK_MODEL",  "anthropic.claude-3-haiku-20240307-v1:0")
POLLY_REGION   = os.getenv("POLLY_REGION",   "ap-south-1")
POLLY_FALLBACK_REGION = os.getenv("POLLY_FALLBACK_REGION", "us-east-1")
POLLY_VOICE    = os.getenv("POLLY_VOICE",    "Ruth")
POLLY_RATE     = os.getenv("POLLY_RATE",     "medium")
POLLY_PITCH    = os.getenv("POLLY_PITCH",    "+4%")

# AWS Clients
bedrock = boto3.client(
    "bedrock-runtime",
    config=Config(region_name=BEDROCK_REGION, retries={"max_attempts": 3, "mode": "adaptive"})
)
polly = boto3.client(
    "polly",
    config=Config(region_name=POLLY_REGION, retries={"max_attempts": 3, "mode": "standard"})
)

# Conversation memory
MAX_TURNS = 10
_history: Dict[str, deque] = defaultdict(lambda: deque(maxlen=MAX_TURNS*2))

def add_turn(session_id: str, role: str, content: str):
    """Add a conversation turn to memory"""
    _history[session_id].append({"role": role, "content": content})

def get_msgs(session_id: str) -> List[Dict]:
    """Get conversation history in Claude format"""
    msgs = []
    for m in _history[session_id]:
        msgs.append({
            "role": "user" if m["role"] == "user" else "assistant",
            "content": [{"type": "text", "text": m["content"]}]
        })
    return msgs

def enforce_identity(text: str) -> str:
    """Remove unwanted identity prefixes"""
    if not text:
        return ""
    # Remove "Rem:" or similar prefixes
    lines = text.strip().split('\n')
    cleaned_lines = []
    for line in lines:
        line = line.strip()
        if ':' in line and len(line.split(':')[0]) < 20:
            # Remove potential "Name:" prefix
            parts = line.split(':', 1)
            if len(parts) > 1:
                line = parts[1].strip()
        cleaned_lines.append(line)
    return '\n'.join(cleaned_lines).strip()

def clamp_sentences(text: str, max_sentences: int = 3) -> str:
    """Limit response to max sentences"""
    if not text:
        return ""
    sentences = re.split(r'[.!?]+', text)
    sentences = [s.strip() for s in sentences if s.strip()]
    return '. '.join(sentences[:max_sentences]) + '.'

def _compose_system(base_prompt: str, style: Optional[str] = None) -> str:
    """Compose system prompt with style"""
    result = base_prompt
    if style:
        style = style.lower().strip()
        if style == "witty":
            result += " Be playful and humorous in your responses."
        elif style == "empathetic":
            result += " Be especially caring and supportive in your responses."
        elif style == "precise":
            result += " Be direct and focused in your responses."
    return result

def _user_for_style(user_text: str, style: Optional[str] = None) -> str:
    """Add style context to user message"""
    if not style:
        return user_text
    style = style.lower().strip()
    if style == "witty":
        return f"{user_text} (Please respond in a witty, playful way)"
    elif style == "empathetic":
        return f"{user_text} (Please respond with empathy and care)"
    elif style == "precise":
        return f"{user_text} (Please respond precisely and directly)"
    return user_text

BEDROCK_MAX_RETRIES = 3

def _retry_sleep(attempt: int):
    """Exponential backoff for retries"""
    time.sleep((2 ** attempt) + random.uniform(0, 1))

def bedrock_reply(system_prompt: str, session_id: str, user_text: str, style: Optional[str] = None) -> str:
    """Get AI response from Bedrock"""
    messages = get_msgs(session_id)
    messages.append({"role":"user","content":[{"type":"text","text":_user_for_style(user_text, style)}]})
    
    s = (style or "").strip().lower()
    temp = 0.7
    if s in ("witty","spicy"): 
        temp = 0.9
    elif s == "precise": 
        temp = 0.4
    elif s == "empathetic": 
        temp = 0.7
        
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 480,
        "temperature": temp,
        "top_p": 0.9,
        "system": _compose_system(system_prompt, style),
        "messages": messages,
    }
    
    last_err = None
    for attempt in range(BEDROCK_MAX_RETRIES):
        try:
            r = bedrock.invoke_model(
                modelId=BEDROCK_MODEL, 
                accept="application/json",
                contentType="application/json", 
                body=json.dumps(body)
            )
            data = json.loads(r["body"].read())
            break
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code", "ClientError")
            if code in {"ThrottlingException", "TooManyRequestsException", "ServiceUnavailableException"}:
                last_err = e
                _retry_sleep(attempt)
                continue
            raise
    else:
        raise last_err or RuntimeError("Bedrock retries exhausted")
    
    out = ""
    for block in data.get("content", []):
        if block.get("type") == "text":
            out += block.get("text") or ""
    
    return clamp_sentences(enforce_identity(out) or "I'm here.")

def polly_tts_with_visemes(text: str, voice: str = None, rate: str = None, pitch: str = None) -> Dict:
    """Generate TTS with visemes using Polly"""
    if not text.strip():
        return {"error": "Empty text"}
    
    voice = voice or POLLY_VOICE
    rate = rate or POLLY_RATE
    pitch = pitch or POLLY_PITCH
    
    ssml = f'<speak><prosody rate="{rate}" pitch="{pitch}">{html.escape(text)}</prosody></speak>'
    
    try:
        response = polly.synthesize_speech(
            Text=ssml,
            OutputFormat='mp3',
            VoiceId=voice,
            TextType='ssml',
            SpeechMarkTypes=['viseme']
        )
        
        audio_stream = response['AudioStream'].read()
        audio_b64 = base64.b64encode(audio_stream).decode('utf-8')
        
        # Get visemes
        viseme_response = polly.synthesize_speech(
            Text=ssml,
            OutputFormat='json',
            VoiceId=voice,
            TextType='ssml',
            SpeechMarkTypes=['viseme']
        )
        
        viseme_data = viseme_response['AudioStream'].read().decode('utf-8')
        visemes = []
        for line in viseme_data.strip().split('\n'):
            if line:
                visemes.append(json.loads(line))
        
        return {
            "audio": audio_b64,
            "visemes": visemes,
            "voice": voice
        }
        
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "ClientError")
        msg = e.response.get("Error", {}).get("Message", str(e))
        return {"error": f"Polly error: {code} - {msg}"}
    except Exception as e:
        return {"error": f"TTS failure: {e.__class__.__name__}"}

def polly_sing_with_visemes(text: str, voice: str = None, rate: str = "slow", pitch: str = "+10%") -> Dict:
    """Generate singing TTS with visemes"""
    if not text.strip():
        return {"error": "Empty lyrics"}
    
    # Use a more musical voice if available
    voice = voice or "Joanna"  # Joanna sounds better for singing
    
    # Add musical SSML
    musical_text = f'<speak><prosody rate="{rate}" pitch="{pitch}"><emphasis level="moderate">{html.escape(text)}</emphasis></prosody></speak>'
    
    return polly_tts_with_visemes(musical_text, voice, rate, pitch)
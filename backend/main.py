from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Depends, Header
from pydantic import BaseModel
from groq import AsyncGroq
import os
import json
from dotenv import load_dotenv
from fastapi.middleware.cors import CORSMiddleware
import shutil

from sqlalchemy.orm import Session
from sqlalchemy import inspect, text
from passlib.context import CryptContext
from jose import JWTError, jwt
from datetime import datetime, timedelta

import models
import schemas
import database

load_dotenv()

api_key = os.getenv("GROQ_API_KEY")
if not api_key:
    print("UYARI: GROQ_API_KEY bulunamadı!")

client = AsyncGroq(api_key=api_key)

app = FastAPI()

models.Base.metadata.create_all(bind=database.engine)


def _ensure_users_current_unit_column() -> None:
    try:
        inspector = inspect(database.engine)
        if "users" not in inspector.get_table_names():
            return

        columns = {col["name"] for col in inspector.get_columns("users")}
        if "current_unit" in columns:
            return

        with database.engine.begin() as conn:
            conn.execute(
                text(
                    "ALTER TABLE users ADD COLUMN current_unit INTEGER DEFAULT 1"
                )
            )
    except Exception as e:
        print(f"UYARI: current_unit migration uygulanamadı: {e}")


_ensure_users_current_unit_column()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- GÜVENLİK AYARLARI ---
SECRET_KEY = os.getenv("SECRET_KEY", "cok_gizli_bir_anahtar_buraya_yaz")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7

pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def get_current_user(token: str, db: Session) -> models.User:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str | None = payload.get("sub")
        if username is None:
            raise HTTPException(status_code=401, detail="Token geçersiz")
    except JWTError:
        raise HTTPException(status_code=401, detail="Token geçersiz")

    user = db.query(models.User).filter(models.User.username == username).first()
    if user is None:
        raise HTTPException(status_code=401, detail="Kullanıcı bulunamadı")
    return user


def _extract_bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(status_code=401, detail="Authorization header eksik")
    parts = authorization.split(" ")
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(status_code=401, detail="Authorization formatı hatalı")
    return parts[1]


def current_user_dep(
    authorization: str | None = Header(default=None),
    db: Session = Depends(database.get_db),
) -> models.User:
    token = _extract_bearer_token(authorization)
    return get_current_user(token, db)


@app.post("/register", response_model=schemas.Token)
def register(user: schemas.UserCreate, db: Session = Depends(database.get_db)):
    db_user = db.query(models.User).filter(models.User.username == user.username).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Bu kullanıcı adı zaten alınmış")

    db_email = db.query(models.User).filter(models.User.email == user.email).first()
    if db_email:
        raise HTTPException(status_code=400, detail="Bu email zaten kullanılıyor")

    hashed_pwd = get_password_hash(user.password)
    new_user = models.User(
        username=user.username,
        email=user.email,
        hashed_password=hashed_pwd,
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    access_token = create_access_token(data={"sub": new_user.username})
    return {"access_token": access_token, "token_type": "bearer"}


@app.post("/login", response_model=schemas.Token)
def login(user_credentials: schemas.UserLogin, db: Session = Depends(database.get_db)):
    user = db.query(models.User).filter(models.User.username == user_credentials.username).first()

    if not user:
        raise HTTPException(status_code=400, detail="Kullanıcı adı veya şifre hatalı")
    if not verify_password(user_credentials.password, user.hashed_password):
        raise HTTPException(status_code=400, detail="Kullanıcı adı veya şifre hatalı")

    access_token = create_access_token(data={"sub": user.username})
    return {"access_token": access_token, "token_type": "bearer"}


@app.get("/users/me", response_model=schemas.UserOut)
def read_users_me(
    authorization: str | None = Header(default=None),
    db: Session = Depends(database.get_db),
):
    token = _extract_bearer_token(authorization)
    user = get_current_user(token, db)
    return user


PLACEMENT_SYSTEM_PROMPT = """
Sen uzman bir İngilizce sınav hazırlayıcısısın.
Görevin: Kullanıcının seviyesini belirlemek için 10 adet çoktan seçmeli soru hazırla.
Sorular A1 seviyesinden başlayıp C1 seviyesine kadar kademeli olarak zorlaşmalı.

KESİNLİKLE ŞU JSON FORMATINDA CEVAP VER:
{
    "questions": [
        {
            "id": 1,
            "question": "İngilizce soru metni",
            "question_tr": "Sorunun Türkçe çevirisi",
            "options": ["A şıkkı", "B şıkkı", "C şıkkı", "D şıkkı"],
            "correct_answer": "Doğru olan şıkkın tam metni"
        }
    ]
}
"""


@app.get("/generate_placement_test", response_model=schemas.PlacementTest)
async def generate_placement_test(current_user: models.User = Depends(current_user_dep)):
    try:
        completion = await client.chat.completions.create(
            messages=[
                {"role": "system", "content": PLACEMENT_SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": "Generate a 10-question placement test ranging from A1 to C1.",
                },
            ],
            model="llama-3.3-70b-versatile",
            temperature=0.3,
            max_tokens=2048,
            response_format={"type": "json_object"},
        )

        content = completion.choices[0].message.content or "{}"
        data = json.loads(content)
        if not isinstance(data, dict) or "questions" not in data:
            raise HTTPException(status_code=500, detail="Test formatı geçersiz")
        return data

    except HTTPException:
        raise
    except Exception as e:
        print(f"Test Hatası: {e}")
        raise HTTPException(status_code=500, detail="Test oluşturulamadı")


@app.get("/profile", response_model=schemas.UserOut)
async def get_profile(
    current_user: models.User = Depends(current_user_dep),
):
    return schemas.UserOut(
        id=current_user.id,
        username=current_user.username,
        xp=current_user.xp,
        level=current_user.level,
        streak=current_user.streak,
    )


@app.post("/submit_placement_test")
async def submit_placement_test(
    result: schemas.TestResult,
    current_user: models.User = Depends(current_user_dep),
    db: Session = Depends(database.get_db),
):
    score = result.correct_count
    new_level = "A1"

    if score >= 9:
        new_level = "C1"
    elif score >= 7:
        new_level = "B2"
    elif score >= 5:
        new_level = "B1"
    elif score >= 3:
        new_level = "A2"
    else:
        new_level = "A1"

    level_map = {"A1": 1, "A2": 2, "B1": 3, "B2": 4, "C1": 5}
    current_user.level = level_map[new_level]
    current_user.xp = int(current_user.xp or 0) + 100

    db.add(current_user)
    db.commit()

    return {
        "score": score,
        "assigned_level": new_level,
        "message": f"Tebrikler! Seviyen {new_level} olarak belirlendi.",
    }

# 1. SENARYO KİMLİKLERİ (AI Personaları)
SCENARIOS = {
    "default": "Sen 'English Buddy' adında yardımsever bir İngilizce öğretmenisin. Öğrenciyle sohbet et.",
    "intro": """
        You are an English teacher. This is the first lesson.
        Start with a friendly greeting and ask the student to introduce themselves.
        Speak ONLY in English.
        Keep it short and encouraging.
    """,
    "cafe": """
        ROLEPLAY BAŞLIYOR. SEN BİR BARİSTASIN.
        Müşteri (kullanıcı) dükkana yeni girdi.
        Onu karşıla ve ne içmek istediğini sor.
        Asla öğretmen gibi davranma, rolünden çıkma.
        Kısa ve hızlı konuş. SADECE İngilizce.
    """,
    "restaurant": """
        ROLEPLAY STARTS. YOU ARE A WAITER/WAITRESS IN A RESTAURANT.
        The customer just sat down.
        Greet them, offer the menu, and ask what they'd like to order.
        Speak ONLY in English. Short and natural.
    """,
    "hotel": """
        ROLEPLAY STARTS. YOU ARE A HOTEL RECEPTIONIST.
        The guest is checking in.
        Ask for their name, booking details, and offer help.
        Speak ONLY in English. Professional and friendly.
    """,
    "doctor": """
        ROLEPLAY STARTS. YOU ARE A DOCTOR.
        The patient is visiting you.
        Ask about symptoms, duration, and give simple advice.
        Speak ONLY in English. Calm and clear.
    """,
    "shopping": """
        ROLEPLAY STARTS. YOU ARE A SHOP ASSISTANT IN A CLOTHING STORE.
        Help the customer find a size, color, and answer questions about price.
        Speak ONLY in English. Friendly and helpful.
    """,
    "taxi": """
        ROLEPLAY STARTS. YOU ARE A TAXI DRIVER.
        The passenger gets in.
        Ask where they want to go, confirm the route, and small talk.
        Speak ONLY in English. Natural and short.
    """,
    "smalltalk": """
        ROLEPLAY STARTS. YOU ARE A FRIENDLY STRANGER.
        Make polite small talk about weather, hobbies, and plans.
        Ask questions and keep the conversation going.
        Speak ONLY in English.
    """,
    "interview": """
        ROLEPLAY BAŞLIYOR. SEN GOOGLE'DA KIDEMLİ YAZILIM MÜHENDİSİSİN.
        Karşındaki aday (kullanıcı) iş görüşmesine geldi.
        Onu profesyonelce karşıla ve kendini tanıtmasını iste.
        Asla 'pratik yapıyoruz' deme, gerçek bir mülakat gibi davran.
        SADECE İngilizce konuş.
    """,
    "airport": """
        ROLEPLAY BAŞLIYOR. SEN PASAPORT KONTROL POLİSİSİN (IMMIGRATION OFFICER).
        Yolcu (kullanıcı) bankoya geldi.
        Pasaportunu iste ve geliş amacını sor.
        Ciddi ve otoriter ol. Gülümseme.
        SADECE İngilizce konuş.
    """,
}


# Seviyelere göre öğrenme yolu
LEVEL_CURRICULUM = {
    1: [  # A1 - Beginner
        {
            "id": 1,
            "type": "chat",
            "title": "Unit 1: Hello & Introductions",
            "description": "Learn basic greetings and introduce yourself.",
            "scenario_id": "intro",
            "icon": "handshake",
        },
        {
            "id": 2,
            "type": "quiz",
            "title": "Unit 2: Basic Grammar",
            "description": "Test your understanding of 'to be' verbs.",
            "quiz_topic": "Basic Greetings and Verb To Be",
            "icon": "quiz",
        },
        {
            "id": 3,
            "type": "chat",
            "title": "Unit 3: At the Cafe",
            "description": "Order drinks and simple food items.",
            "scenario_id": "cafe",
            "icon": "coffee",
        },
        {
            "id": 4,
            "type": "quiz",
            "title": "Unit 4: Food Vocabulary",
            "description": "Test your cafe and food vocabulary.",
            "quiz_topic": "Food and Drinks Vocabulary",
            "icon": "quiz",
        },
        {
            "id": 5,
            "type": "chat",
            "title": "Unit 5: Asking for Directions",
            "description": "Learn how to ask for and give directions.",
            "scenario_id": "directions",
            "icon": "map",
        },
        {
            "id": 6,
            "type": "quiz",
            "title": "Unit 6: Prepositions Quiz",
            "description": "Test your knowledge of prepositions.",
            "quiz_topic": "Prepositions of Place",
            "icon": "quiz",
        },
    ],
    2: [  # A2 - Elementary
        {
            "id": 7,
            "type": "chat",
            "title": "Unit 7: Daily Routine",
            "description": "Talk about your daily activities and habits.",
            "scenario_id": "daily_routine",
            "icon": "schedule",
        },
        {
            "id": 8,
            "type": "quiz",
            "title": "Unit 8: Present Tense",
            "description": "Test present simple and continuous tenses.",
            "quiz_topic": "Present Tense Review",
            "icon": "quiz",
        },
        {
            "id": 9,
            "type": "chat",
            "title": "Unit 9: Shopping",
            "description": "Buy clothes and ask about prices.",
            "scenario_id": "shopping",
            "icon": "shopping_bag",
        },
        {
            "id": 10,
            "type": "quiz",
            "title": "Unit 10: Clothes Vocabulary",
            "description": "Test your shopping and clothes vocabulary.",
            "quiz_topic": "Clothes and Shopping",
            "icon": "quiz",
        },
        {
            "id": 11,
            "type": "chat",
            "title": "Unit 11: Weather Talk",
            "description": "Discuss weather and make small talk.",
            "scenario_id": "weather",
            "icon": "cloud",
        },
        {
            "id": 12,
            "type": "quiz",
            "title": "Unit 12: Past Tense",
            "description": "Test simple past tense and time expressions.",
            "quiz_topic": "Past Tense Review",
            "icon": "quiz",
        },
    ],
    3: [  # B1 - Intermediate
        {
            "id": 13,
            "type": "chat",
            "title": "Unit 13: Job Interview",
            "description": "Practice job interview questions and answers.",
            "scenario_id": "job_interview",
            "icon": "business_center",
        },
        {
            "id": 14,
            "type": "quiz",
            "title": "Unit 14: Conditionals",
            "description": "Test conditional sentences and future possibilities.",
            "quiz_topic": "Conditional Sentences",
            "icon": "quiz",
        },
        {
            "id": 15,
            "type": "chat",
            "title": "Unit 15: At the Doctor",
            "description": "Describe symptoms and medical problems.",
            "scenario_id": "doctor",
            "icon": "local_hospital",
        },
        {
            "id": 16,
            "type": "quiz",
            "title": "Unit 16: Health Vocabulary",
            "description": "Test medical and health vocabulary.",
            "quiz_topic": "Health and Medicine",
            "icon": "quiz",
        },
        {
            "id": 17,
            "type": "chat",
            "title": "Unit 17: Travel Planning",
            "description": "Plan trips and discuss travel experiences.",
            "scenario_id": "travel",
            "icon": "flight",
        },
        {
            "id": 18,
            "type": "quiz",
            "title": "Unit 18: Travel Vocabulary",
            "description": "Test travel and transportation vocabulary.",
            "quiz_topic": "Travel and Transportation",
            "icon": "quiz",
        },
    ],
    4: [  # B2 - Upper Intermediate
        {
            "id": 19,
            "type": "chat",
            "title": "Unit 19: Business Meeting",
            "description": "Participate in business discussions.",
            "scenario_id": "business_meeting",
            "icon": "groups",
        },
        {
            "id": 20,
            "type": "quiz",
            "title": "Unit 20: Passive Voice",
            "description": "Test passive voice and formal structures.",
            "quiz_topic": "Passive Voice and Formal Language",
            "icon": "quiz",
        },
        {
            "id": 21,
            "type": "chat",
            "title": "Unit 21: Academic Discussion",
            "description": "Discuss academic topics and opinions.",
            "scenario_id": "academic",
            "icon": "school",
        },
        {
            "id": 22,
            "type": "quiz",
            "title": "Unit 22: Advanced Vocabulary",
            "description": "Test academic and formal vocabulary.",
            "quiz_topic": "Academic Vocabulary",
            "icon": "quiz",
        },
        {
            "id": 23,
            "type": "chat",
            "title": "Unit 23: Debate Skills",
            "description": "Practice expressing and defending opinions.",
            "scenario_id": "debate",
            "icon": "forum",
        },
        {
            "id": 24,
            "type": "quiz",
            "title": "Unit 24: Complex Sentences",
            "description": "Test complex sentence structures.",
            "quiz_topic": "Complex Sentences and Connectors",
            "icon": "quiz",
        },
    ],
    5: [  # C1 - Advanced
        {
            "id": 25,
            "type": "chat",
            "title": "Unit 25: Professional Presentation",
            "description": "Deliver professional presentations.",
            "scenario_id": "presentation",
            "icon": "slideshow",
        },
        {
            "id": 26,
            "type": "quiz",
            "title": "Unit 26: Advanced Grammar",
            "description": "Test advanced grammar and nuances.",
            "quiz_topic": "Advanced Grammar Review",
            "icon": "quiz",
        },
        {
            "id": 27,
            "type": "chat",
            "title": "Unit 27: Negotiation Skills",
            "description": "Practice business negotiation tactics.",
            "scenario_id": "negotiation",
            "icon": "handshake",
        },
        {
            "id": 28,
            "type": "quiz",
            "title": "Unit 28: Business Vocabulary",
            "description": "Test advanced business terminology.",
            "quiz_topic": "Business and Professional Vocabulary",
            "icon": "quiz",
        },
        {
            "id": 29,
            "type": "chat",
            "title": "Unit 28: Cultural Discussion",
            "description": "Discuss cultural topics and current events.",
            "scenario_id": "cultural",
            "icon": "public",
        },
        {
            "id": 30,
            "type": "quiz",
            "title": "Unit 30: Proficiency Review",
            "description": "Comprehensive test of all skills.",
            "quiz_topic": "C1 Proficiency Test",
            "icon": "quiz",
        },
    ]
}

# Legacy support - flatten all units for backward compatibility
CURRICULUM = []
for level_units in LEVEL_CURRICULUM.values():
    CURRICULUM.extend(level_units)


class QuizQuestion(BaseModel):
    id: int
    question: str
    options: list[str]
    correct_answer: str


class QuizResponse(BaseModel):
    questions: list[QuizQuestion]


class QuizRequest(BaseModel):
    topic: str


@app.post("/generate_quiz", response_model=QuizResponse)
async def generate_quiz(
    req: QuizRequest,
    current_user: models.User = Depends(current_user_dep),
):
    try:
        system_prompt = f"""
Sen bir İngilizce öğretmenisin.
Görevin: '{req.topic}' konusu hakkında A1-A2 seviyesinde 5 adet çoktan seçmeli soru hazırla.
Sorular kısa ve net olsun.

JSON FORMATI:
{{
    \"questions\": [
        {{
            \"id\": 1,
            \"question\": \"She ___ a student.\",
            \"options\": [\"is\", \"are\", \"am\", \"be\"],
            \"correct_answer\": \"is\"
        }}
    ]
}}
"""

        completion = await client.chat.completions.create(
            messages=[{"role": "system", "content": system_prompt}],
            model="llama-3.3-70b-versatile",
            temperature=0.3,
            max_tokens=1024,
            response_format={"type": "json_object"},
        )

        content = completion.choices[0].message.content or "{}"
        data = json.loads(content)
        if not isinstance(data, dict) or "questions" not in data:
            raise HTTPException(status_code=500, detail="Quiz formatı geçersiz")
        return data
    except HTTPException:
        raise
    except Exception as e:
        print(f"Quiz Hatası: {e}")
        raise HTTPException(status_code=500, detail="Quiz oluşturulamadı")


class Flashcard(BaseModel):
    term: str
    meaning: str
    meaning_tr: str
    example: str
    example_tr: str


class FlashcardsResponse(BaseModel):
    cards: list[Flashcard]


@app.get("/generate_flashcards", response_model=FlashcardsResponse)
async def generate_flashcards(current_user: models.User = Depends(current_user_dep)):
    try:
        import random
        import datetime
        
        # Rastgele kategoriler seçerek çeşitlilik sağla
        categories = [
            "daily conversations and social interactions",
            "business and work situations", 
            "emotions and feelings",
            "travel and transportation",
            "food and dining",
            "technology and modern life",
            "health and wellness",
            "education and learning",
            "weather and nature",
            "money and finance"
        ]
        
        selected_categories = random.sample(categories, 3)
        
        system_prompt = f"""
You are an English teacher.
Create 7 daily English idiom/phrase flashcards for learners (A2-B2 level).

Focus on these categories: {", ".join(selected_categories)}
Use different idioms each time - be creative and varied!

Return ONLY valid JSON with this format:
{{
  "cards": [
    {{
      "term": "break the ice",
      "meaning": "to make people feel more comfortable in a social situation",
      "meaning_tr": "sohbeti başlatmak / ortamı yumuşatmak",
      "example": "To break the ice, I asked her about her hobbies.",
      "example_tr": "Ortamı yumuşatmak için ona hobilerini sordum."
    }}
  ]
}}

IMPORTANT: Always generate DIFFERENT idioms each time. Don't repeat the same ones.
"""

        completion = await client.chat.completions.create(
            messages=[{"role": "system", "content": system_prompt}],
            model="llama-3.3-70b-versatile",
            temperature=0.9,  # Artırılmış rastgelelik
            max_tokens=1200,
            response_format={"type": "json_object"},
        )

        content = completion.choices[0].message.content or "{}"
        data = json.loads(content)
        if not isinstance(data, dict) or "cards" not in data:
            raise HTTPException(status_code=500, detail="Flashcard formatı geçersiz")
        return data

    except HTTPException:
        raise
    except Exception as e:
        print(f"Flashcards Hatası: {e}")
        raise HTTPException(status_code=500, detail="Flashcards oluşturulamadı")


@app.get("/daily_test")
def get_daily_test(current_user: models.User = Depends(current_user_dep)):
    try:
        import random
        
        # Boşluk doldurma soruları havuzu
        fill_blank_questions = [
            {
                "sentence": "She ___ to school every day.",
                "answer": "goes",
                "turkish": "O her gün okula gider."
            },
            {
                "sentence": "They ___ playing football now.",
                "answer": "are",
                "turkish": "Onlar şimdi futbol oynuyorlar."
            },
            {
                "sentence": "I ___ my homework yesterday.",
                "answer": "did",
                "turkish": "Ben dün ödevimi yaptım."
            },
            {
                "sentence": "We will ___ to the cinema tomorrow.",
                "answer": "go",
                "turkish": "Biz yarın sinemaya gideceğiz."
            },
            {
                "sentence": "He ___ English very well.",
                "answer": "speaks",
                "turkish": "O İngilizceyi çok iyi konuşur."
            },
            {
                "sentence": "The cat ___ on the table.",
                "answer": "is",
                "turkish": "Kedi masanın üzerindedir."
            },
            {
                "sentence": "They ___ finished their work.",
                "answer": "have",
                "turkish": "Onlar işlerini bitirdiler."
            },
            {
                "sentence": "She ___ coffee in the morning.",
                "answer": "drinks",
                "turkish": "O sabah kahve içer."
            },
            {
                "sentence": "I ___ reading a book now.",
                "answer": "am",
                "turkish": "Ben şimdi bir kitap okuyorum."
            },
            {
                "sentence": "He ___ to music every evening.",
                "answer": "listens",
                "turkish": "O her akşam müzik dinler."
            },
            {
                "sentence": "We ___ at home last night.",
                "answer": "were",
                "turkish": "Biz dün gece evdeydik."
            },
            {
                "sentence": "She ___ her nails every week.",
                "answer": "cuts",
                "turkish": "O her hafta tırnaklarını keser."
            },
            {
                "sentence": "They ___ going to visit us.",
                "answer": "are",
                "turkish": "Onlar bizi ziyaret edecekler."
            },
            {
                "sentence": "I ___ a new car last month.",
                "answer": "bought",
                "turkish": "Ben geçen ay yeni bir araba aldım."
            },
            {
                "sentence": "The sun ___ in the east.",
                "answer": "rises",
                "turkish": "Güneş doğudan doğar."
            },
            {
                "sentence": "She ___ French and Spanish.",
                "answer": "speaks",
                "turkish": "O Fransızca ve İspanyolca konuşur."
            },
            {
                "sentence": "We ___ dinner at 7 PM.",
                "answer": "have",
                "turkish": "Biz akşam 7'de yemek yeriz."
            },
            {
                "sentence": "He ___ his glasses every day.",
                "answer": "wears",
                "turkish": "O her gün gözlük takar."
            },
            {
                "sentence": "They ___ married last year.",
                "answer": "got",
                "turkish": "Onlar geçen yıl evlendiler."
            },
            {
                "sentence": "I ___ to the store yesterday.",
                "answer": "went",
                "turkish": "Ben dün mağazaya gittim."
            }
        ]
        
        # Kullanıcı seviyesine göre soru seçimi
        user_level = int(getattr(current_user, "level", 1) or 1)
        
        # Seviyeye göre soru havuzu ayarla
        if user_level <= 2:  # A1-A2
            selected_questions = fill_blank_questions[:15]
        elif user_level <= 3:  # B1
            selected_questions = fill_blank_questions[:18]
        else:  # B2-C1
            selected_questions = fill_blank_questions
        
        # Rastgele 10 soru seç
        questions = random.sample(selected_questions, min(10, len(selected_questions)))
        
        return {"questions": questions}
        
    except Exception as e:
        print(f"Daily Test Hatası: {e}")
        raise HTTPException(status_code=500, detail="Test oluşturulamadı")


@app.post("/complete_daily_test")
def complete_daily_test(current_user: models.User = Depends(current_user_dep), db: Session = Depends(database.get_db)):
    try:
        # 100 soru tamamlama XP'si
        current_user.xp = int(current_user.xp or 0) + 50
        
        # Seviye kontrolü
        new_level = (current_user.xp // 1000) + 1
        if new_level > 5:
            new_level = 5
            
        if new_level > int(current_user.level or 1):
            current_user.level = new_level
            level_up = True
        else:
            level_up = False
        
        db.add(current_user)
        db.commit()
        
        return {
            "message": "Daily test completed! +50 XP",
            "new_level": new_level,
            "level_up": level_up,
            "total_xp": current_user.xp
        }
        
    except Exception as e:
        print(f"Complete Daily Test Hatası: {e}")
        raise HTTPException(status_code=500, detail="Test tamamlanamadı")


@app.get("/roadmap")
def get_roadmap(current_user: models.User = Depends(current_user_dep)):
    user_level = int(getattr(current_user, "level", 1) or 1)
    current_unit = int(getattr(current_user, "current_unit", 1) or 1)
    
    # Tüm unit'leri 1-30 sıralı şekilde göster
    roadmap_data = []
    
    for unit in CURRICULUM:
        status = "locked"
        if unit["id"] < current_unit:
            status = "completed"
        elif unit["id"] == current_unit:
            status = "active"

        roadmap_data.append({**unit, "status": status})

    return {
        "current_unit": current_unit,
        "user_level": user_level,
        "units": roadmap_data
    }


@app.post("/complete_unit")
def complete_unit(
    current_user: models.User = Depends(current_user_dep),
    db: Session = Depends(database.get_db),
):
    current_unit = int(getattr(current_user, "current_unit", 1) or 1)
    user_level = int(getattr(current_user, "level", 1) or 1)
    
    # XP ekle
    current_user.xp = int(current_user.xp or 0) + 50
    
    # Seviye atlama kontrolü (her 1000 XP'de bir seviye)
    new_level = (current_user.xp // 1000) + 1
    if new_level > 5:
        new_level = 5  # Max seviye C1
    
    # Seviye atladıysa ve yeni seviyenin ilk unit'ine geçmesi gerekiyorsa
    if new_level > user_level:
        current_user.level = new_level
        # Yeni seviyenin ilk unit'ini bul
        if new_level in LEVEL_CURRICULUM and LEVEL_CURRICULUM[new_level]:
            first_unit_of_new_level = LEVEL_CURRICULUM[new_level][0]["id"]
            current_user.current_unit = first_unit_of_new_level
        else:
            current_user.current_unit = current_unit + 1
    else:
        # Aynı seviyede sonraki unit'e geç
        max_unit = len(CURRICULUM)
        if current_unit < max_unit:
            current_user.current_unit = current_unit + 1
        else:
            current_user.current_unit = current_unit

    db.add(current_user)
    db.commit()

    return {
        "message": "Unit completed!",
        "new_unit": int(current_user.current_unit or current_unit),
        "new_level": int(current_user.level or user_level),
        "level_up": new_level > user_level,
    }

class UserMessage(BaseModel):
    message: str
    scenario: str = "default"  # Varsayılan olarak normal hoca


class StartChatRequest(BaseModel):
    scenario: str


class WordRequest(BaseModel):
    word: str


class TranslateRequest(BaseModel):
    text: str


class TranslateResponse(BaseModel):
    translation: str

# StoryRequest için model
class StoryRequest(BaseModel):
    topic: str
    level: str  # A1, A2, B1, B2, C1

SYSTEM_PROMPT = """
Sen "English Buddy" adında bir İngilizce öğretmenisin.
Görevin:
1. Kullanıcının mesajına doğal, konuşma diline uygun bir cevap ver (reply).
2. Kullanıcının İngilizcesinde bir gramer veya kelime hatası var mı analiz et.
3. Cevabını SADECE geçerli bir JSON formatında döndür. Asla yorum ekleme.

JSON Formatı şöyle olmalı:
{
    "reply": "Buraya senin vereceğin sohbet cevabı gelecek (Kullanıcı Türkçe konuştuysa Türkçe, İngilizce konuştuysa İngilizce)",
    "has_mistake": true veya false,
    "correction": "Eğer hata varsa, cümlenin doğrusunu buraya yaz (yoksa boş bırak)",
    "explanation_tr": "Eğer hata varsa, hatayı Türkçe olarak kısaca açıkla (yoksa boş bırak)"
}
"""

# HİKAYE SİSTEM PROMPTU
STORY_SYSTEM_PROMPT = """
Sen uzman bir İngilizce içerik üreticisisin.
Görevin: Verilen konu (topic) ve seviyeye (level) uygun kısa bir İngilizce hikaye yazmak.
Çıktı SADECE geçerli bir JSON olmalı.

KRİTİK YAZIM KURALI (story alanı için):
- Metin normal İngilizce gibi yazılmalı: kelimeler arasında TEK boşluk olmalı.
- Asla kelimeleri bitişik yazma (ör: "Ilikefootball" YASAK).
- Noktalama işaretleri doğru kullanılmalı ("word,", "word." gibi).
- Okunabilirlik için 2-4 kısa paragraf kullanabilir, paragrafları "\n\n" ile ayırabilirsin.

İstenen JSON Formatı:
{
    "title": "Hikayenin Başlığı",
    "story": "Hikayenin metni (yaklaşık 100-150 kelime)",
    "keywords": [
        {"word": "apple", "meaning": "elma"},
        {"word": "run", "meaning": "koşmak"}
    ],
    "quiz": [
        {
            "question": "Hikayeye göre ...?",
            "options": ["A şıkkı", "B şıkkı", "C şıkkı"],
            "answer": "Doğru cevap metni"
        }
    ]
}
"""

@app.get("/")
def read_root():
    return {"status": "Backend Hazır", "features": ["Chat", "Voice"]}

# 1. METİN SOHBETİ (Eski Endpoint)
@app.post("/chat")
async def chat_endpoint(user_input: UserMessage):
    try:
        system_instruction = SCENARIOS.get(user_input.scenario, SCENARIOS["default"])

        full_system_prompt = system_instruction + """

        KESİNLİKLE ŞU JSON FORMATINDA CEVAP VER:
        {
            "reply": "Rolüne uygun cevabın",
            "has_mistake": true/false,
            "correction": "Düzeltme (varsa)",
            "explanation_tr": "Hatayı Türkçe açıkla"
        }
        """

        completion = await client.chat.completions.create(
            messages=[
                {"role": "system", "content": full_system_prompt},
                {"role": "user", "content": user_input.message},
            ],
            model="llama-3.3-70b-versatile",
            temperature=0.7,
            max_tokens=1024,
            response_format={"type": "json_object"},
        )

        response_content = completion.choices[0].message.content or "{}"
        try:
            response_json = json.loads(response_content)
        except Exception:
            response_json = {
                "reply": response_content,
                "has_mistake": False,
                "correction": "",
                "explanation_tr": "",
            }

        if not isinstance(response_json, dict):
            response_json = {
                "reply": str(response_json),
                "has_mistake": False,
                "correction": "",
                "explanation_tr": "",
            }

        response_json.setdefault("reply", "")
        response_json.setdefault("has_mistake", False)
        response_json.setdefault("correction", "")
        response_json.setdefault("explanation_tr", "")

        return {"response": response_json}
    except Exception as e:
        print(f"Chat Hatası: {e}")
        return {
            "response": {
                "reply": "Bağlantı hatası oluştu.",
                "has_mistake": False,
                "correction": "",
                "explanation_tr": "",
            }
        }


@app.post("/start_chat")
async def start_chat_endpoint(request: StartChatRequest):
    try:
        scenario_prompt = SCENARIOS.get(request.scenario, SCENARIOS["default"])

        system_instruction = scenario_prompt + """

        GÖREVİN: Bu senaryoya uygun İLK AÇILIŞ CÜMLESİNİ kur.

        KESİNLİKLE ŞU JSON FORMATINDA CEVAP VER:
        {
            "reply": "Senin açılış cümlen",
            "has_mistake": false,
            "correction": "",
            "explanation_tr": ""
        }
        """

        completion = await client.chat.completions.create(
            messages=[
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": "Start the conversation now."},
            ],
            model="llama-3.3-70b-versatile",
            temperature=0.8,
            max_tokens=500,
            response_format={"type": "json_object"},
        )

        response_content = completion.choices[0].message.content or "{}"
        try:
            response_json = json.loads(response_content)
        except Exception:
            response_json = {
                "reply": response_content,
                "has_mistake": False,
                "correction": "",
                "explanation_tr": "",
            }

        if not isinstance(response_json, dict):
            response_json = {
                "reply": str(response_json),
                "has_mistake": False,
                "correction": "",
                "explanation_tr": "",
            }

        response_json.setdefault("reply", "")
        response_json.setdefault("has_mistake", False)
        response_json.setdefault("correction", "")
        response_json.setdefault("explanation_tr", "")

        return {"response": response_json}

    except Exception as e:
        print(f"Start Chat Hatası: {e}")
        return {
            "response": {
                "reply": "Hello! Ready to start?",
                "has_mistake": False,
                "correction": "",
                "explanation_tr": "",
            }
        }


@app.post("/define")
async def define_word(request: WordRequest):
    try:
        system_prompt = """
        Sen bir İngilizce-Türkçe sözlüksün.
        Görevin: Verilen İngilizce kelimenin Türkçe anlamını ve basit bir İngilizce örnek cümlesini JSON olarak vermek.

        FORMAT:
        {
            "word": "kelime",
            "meaning": "Türkçe karşılığı (kısa)",
            "example": "İngilizce örnek cümle."
        }
        """

        completion = await client.chat.completions.create(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"Define: {request.word}"},
            ],
            model="llama-3.3-70b-versatile",
            temperature=0.3,
            max_tokens=200,
            response_format={"type": "json_object"},
        )

        response_content = completion.choices[0].message.content or "{}"
        try:
            data = json.loads(response_content)
        except Exception:
            data = {"word": request.word, "meaning": "Hata oluştu", "example": "-"}

        if not isinstance(data, dict):
            data = {"word": request.word, "meaning": "Hata oluştu", "example": "-"}

        data.setdefault("word", request.word)
        data.setdefault("meaning", "")
        data.setdefault("example", "")
        return data

    except Exception as e:
        print(f"Sözlük Hatası: {e}")
        return {"word": request.word, "meaning": "Hata oluştu", "example": "-"}


@app.post("/translate", response_model=TranslateResponse)
async def translate_text(request: TranslateRequest):
    try:
        system_prompt = """
You are a professional translator.
Translate the given English text into natural Turkish.
Return ONLY valid JSON with this format:
{
  \"translation\": \"...\"
}
"""

        completion = await client.chat.completions.create(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": request.text},
            ],
            model="llama-3.3-70b-versatile",
            temperature=0.2,
            max_tokens=2048,
            response_format={"type": "json_object"},
        )

        response_content = completion.choices[0].message.content or "{}"
        data = json.loads(response_content)
        if not isinstance(data, dict):
            raise HTTPException(status_code=500, detail="Invalid translation")

        translation = (data.get("translation") or "").strip()
        return {"translation": translation}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Translate Hatası: {e}")
        raise HTTPException(status_code=500, detail="Çeviri yapılamadı")

# 2. SESLİ SOHBET ENDPOINT'İ
@app.post("/voice")
async def voice_endpoint(
    file: UploadFile = File(...),
    lang: str = Form(...) # YENİ: Flutter'dan dil kodunu (tr veya en) alıyoruz
):
    try:
        temp_filename = f"temp_{file.filename}"
        if not temp_filename.endswith(".m4a"):
            temp_filename += ".m4a"

        with open(temp_filename, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # Groq Whisper Çağrısı
        with open(temp_filename, "rb") as audio_file:
            transcription = await client.audio.transcriptions.create(
                file=(temp_filename, audio_file.read()),
                model="whisper-large-v3",
                
                # BURASI KRİTİK: Dili Flutter'dan gelen bilgiye göre zorluyoruz
                language=lang, 
                
                response_format="json",
                temperature=0.0
            )
        
        user_text = transcription.text
        
        if os.path.exists(temp_filename):
            os.remove(temp_filename)

        # AI Cevabı
        full_ai_data = await get_ai_response(user_text)
        ai_response = full_ai_data["response"]

        return {
            "user_text": user_text,  # Senin dediğini de geri dönelim ki ekranda gösterelim
            "response": ai_response
        }

    except Exception as e:
        print(f"Ses hatası: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/story")
async def generate_story(request: StoryRequest):
    try:
        user_prompt = f"Topic: {request.topic}, Level: {request.level}. Create a story."

        completion = await client.chat.completions.create(
            messages=[
                {"role": "system", "content": STORY_SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt}
            ],
            model="llama-3.3-70b-versatile",
            temperature=0.7,
            max_tokens=2048,
            response_format={"type": "json_object"}
        )

        response_content = completion.choices[0].message.content or "{}"
        try:
            data = json.loads(response_content)
        except Exception:
            raise HTTPException(status_code=500, detail="Invalid JSON returned from model")

        if not isinstance(data, dict):
            raise HTTPException(status_code=500, detail="Invalid JSON returned from model")

        story_text = (data.get("story") or "").strip()

        def _needs_spacing_fix(text: str) -> bool:
            if not text:
                return False
            letters = sum(1 for c in text if c.isalpha())
            spaces = text.count(" ")
            longest_run = 0
            run = 0
            for c in text:
                if c.isalpha():
                    run += 1
                    if run > longest_run:
                        longest_run = run
                else:
                    run = 0

            # Heuristics: very few spaces compared to letters, or extremely long alpha runs.
            if letters >= 80 and spaces <= 3:
                return True
            if letters > 0 and spaces / max(letters, 1) < 0.03:
                return True
            if longest_run >= 35:
                return True
            return False

        if _needs_spacing_fix(story_text):
            fix_system_prompt = """
You are a text cleaner.
The given English story has missing spaces or poor formatting.
Rewrite the SAME story in natural English with proper spacing and punctuation.

Rules:
- Do NOT change the meaning.
- Only fix spacing/punctuation/newlines.
- Keep it readable; you may split into 2-4 paragraphs using \n\n.

Return ONLY valid JSON:
{ "story": "..." }
"""

            fix_completion = await client.chat.completions.create(
                messages=[
                    {"role": "system", "content": fix_system_prompt},
                    {"role": "user", "content": story_text},
                ],
                model="llama-3.3-70b-versatile",
                temperature=0.0,
                max_tokens=2048,
                response_format={"type": "json_object"},
            )

            fix_content = fix_completion.choices[0].message.content or "{}"
            try:
                fix_data = json.loads(fix_content)
            except Exception:
                fix_data = {}

            if isinstance(fix_data, dict):
                fixed_story = (fix_data.get("story") or "").strip()
                if fixed_story:
                    data["story"] = fixed_story

        return data

    except HTTPException:
        raise
    except Exception as e:
        print(f"Hikaye Hatası: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# Yardımcı Fonksiyon (Kod tekrarını önlemek için)
async def get_ai_response(text: str):
    try:
        completion = await client.chat.completions.create(
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": text}
            ],
            model="llama-3.3-70b-versatile",
            temperature=0.7,
            max_tokens=1024,
            response_format={"type": "json_object"},
        )
        response_content = completion.choices[0].message.content or "{}"

        try:
            response_json = json.loads(response_content)
        except Exception:
            response_json = {
                "reply": response_content,
                "has_mistake": False,
                "correction": "",
                "explanation_tr": "",
            }

        if not isinstance(response_json, dict):
            response_json = {
                "reply": str(response_json),
                "has_mistake": False,
                "correction": "",
                "explanation_tr": "",
            }

        response_json.setdefault("reply", "")
        response_json.setdefault("has_mistake", False)
        response_json.setdefault("correction", "")
        response_json.setdefault("explanation_tr", "")

        return {"response": response_json}
    except Exception as e:
        print(f"AI Hatası: {e}")
        error_json = {
            "reply": "Üzgünüm, şu an bağlantımda bir sorun var.",
            "has_mistake": False,
            "correction": "",
            "explanation_tr": "",
        }
        return {"response": error_json}

from pydantic import BaseModel


class UserCreate(BaseModel):
    username: str
    email: str
    password: str


class UserLogin(BaseModel):
    username: str
    password: str


class Token(BaseModel):
    access_token: str
    token_type: str


class UserOut(BaseModel):
    id: int
    username: str
    xp: int
    level: int
    streak: int

    class Config:
        from_attributes = True


class TestQuestion(BaseModel):
    id: int
    question: str
    question_tr: str
    options: list[str]
    correct_answer: str


class PlacementTest(BaseModel):
    questions: list[TestQuestion]


class TestResult(BaseModel):
    correct_count: int


class QuizQuestion(BaseModel):
    id: int
    question: str
    question_tr: str
    options: list[str]
    correct_answer: str


class QuizResponse(BaseModel):
    answers: list[str]


class QuizRequest(BaseModel):
    topic: str


class Flashcard(BaseModel):
    idiom: str
    meaning: str
    meaning_tr: str
    example: str
    example_tr: str


class FlashcardsResponse(BaseModel):
    flashcards: list[Flashcard]

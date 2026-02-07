from sqlalchemy import Column, Integer, String, DateTime
from database import Base
import datetime


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)

    xp = Column(Integer, default=0)
    level = Column(Integer, default=1)
    streak = Column(Integer, default=0)
    last_login = Column(DateTime, default=datetime.datetime.utcnow)

    current_unit = Column(Integer, default=1)

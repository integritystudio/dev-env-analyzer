"""
Schema.org-based Pydantic models for Fisterra dance/arts organization
Defines the data structures and relationships for graph and SQL databases
"""

from datetime import datetime, date
from typing import List, Optional, Union, Dict, Any
from pydantic import BaseModel, Field, HttpUrl, EmailStr
from enum import Enum


class SchemaOrgBase(BaseModel):
    """Base class for all schema.org entities"""
    id: Optional[str] = Field(None, description="Unique identifier")
    type: str = Field(..., description="Schema.org @type")
    name: str = Field(..., description="Name of the entity")
    description: Optional[str] = Field(None, description="Description")
    url: Optional[HttpUrl] = Field(None, description="URL")
    image: Optional[List[HttpUrl]] = Field(None, description="Images")
    created_at: datetime = Field(default_factory=datetime.now)
    updated_at: datetime = Field(default_factory=datetime.now)


class EventStatus(str, Enum):
    """Event status enumeration"""
    CANCELLED = "EventCancelled"
    MOVED_ONLINE = "EventMovedOnline"
    POSTPONED = "EventPostponed"
    RESCHEDULED = "EventRescheduled"
    SCHEDULED = "EventScheduled"


class EventAttendanceMode(str, Enum):
    """Event attendance mode enumeration"""
    MIXED = "MixedEventAttendanceMode"
    OFFLINE = "OfflineEventAttendanceMode"
    ONLINE = "OnlineEventAttendanceMode"


class PostalAddress(BaseModel):
    """Schema.org PostalAddress"""
    type: str = Field(default="PostalAddress")
    street_address: Optional[str] = Field(None, alias="streetAddress")
    address_locality: Optional[str] = Field(None, alias="addressLocality")
    address_region: Optional[str] = Field(None, alias="addressRegion")
    postal_code: Optional[str] = Field(None, alias="postalCode")
    address_country: Optional[str] = Field(None, alias="addressCountry")


class Place(SchemaOrgBase):
    """Schema.org Place"""
    type: str = Field(default="Place")
    address: Optional[PostalAddress] = None
    geo: Optional[Dict[str, float]] = None  # GeoCoordinates
    telephone: Optional[str] = None
    maximum_attendee_capacity: Optional[int] = Field(None, alias="maximumAttendeeCapacity")


class Person(SchemaOrgBase):
    """Schema.org Person"""
    type: str = Field(default="Person")
    given_name: Optional[str] = Field(None, alias="givenName")
    family_name: Optional[str] = Field(None, alias="familyName")
    email: Optional[EmailStr] = None
    telephone: Optional[str] = None
    job_title: Optional[str] = Field(None, alias="jobTitle")
    affiliation: Optional[List[str]] = None  # Organizations
    knows_about: Optional[List[str]] = Field(None, alias="knowsAbout")  # Skills/expertise
    
    # Dance-specific properties
    dance_styles: Optional[List[str]] = Field(None, description="Dance styles taught/performed")
    instructor_level: Optional[str] = Field(None, description="Instructor certification level")


class Organization(SchemaOrgBase):
    """Schema.org Organization"""
    type: str = Field(default="Organization")
    legal_name: Optional[str] = Field(None, alias="legalName")
    email: Optional[EmailStr] = None
    telephone: Optional[str] = None
    address: Optional[PostalAddress] = None
    founder: Optional[List[str]] = None  # Person IDs
    founding_date: Optional[date] = Field(None, alias="foundingDate")
    members: Optional[List[str]] = None  # Person IDs
    
    # Arts organization specific
    artistic_genre: Optional[List[str]] = Field(None, alias="artisticGenre")
    mission_statement: Optional[str] = Field(None, description="Organization mission")


class DanceGroup(Organization):
    """Schema.org DanceGroup (subclass of Organization)"""
    type: str = Field(default="DanceGroup")
    genre: Optional[List[str]] = None  # Dance genres/styles
    
    # Dance group specific properties
    dance_styles: List[str] = Field(default_factory=list, description="Primary dance styles")
    performance_history: Optional[List[str]] = Field(None, description="Notable performances")
    active_since: Optional[date] = Field(None, description="When group became active")


class Offer(BaseModel):
    """Schema.org Offer"""
    type: str = Field(default="Offer")
    price: Optional[float] = None
    price_currency: str = Field(default="USD", alias="priceCurrency")
    availability: Optional[str] = None  # InStock, OutOfStock, etc.
    valid_from: Optional[datetime] = Field(None, alias="validFrom")
    valid_through: Optional[datetime] = Field(None, alias="validThrough")


class Event(SchemaOrgBase):
    """Schema.org Event base class"""
    type: str = Field(default="Event")
    start_date: datetime = Field(..., alias="startDate")
    end_date: Optional[datetime] = Field(None, alias="endDate")
    location: Optional[Union[str, Place]] = None  # Can be Place ID or Place object
    organizer: Optional[Union[str, Organization]] = None  # Organization ID or object
    performer: Optional[List[Union[str, Person]]] = None  # Person IDs or objects
    audience: Optional[str] = None  # Target audience
    event_status: EventStatus = Field(default=EventStatus.SCHEDULED, alias="eventStatus")
    event_attendance_mode: EventAttendanceMode = Field(
        default=EventAttendanceMode.OFFLINE, 
        alias="eventAttendanceMode"
    )
    maximum_attendee_capacity: Optional[int] = Field(None, alias="maximumAttendeeCapacity")
    offers: Optional[List[Offer]] = None
    
    # Additional properties
    registration_url: Optional[HttpUrl] = Field(None, alias="registrationUrl")
    prerequisites: Optional[List[str]] = None
    skill_level: Optional[str] = Field(None, description="Required skill level")


class DanceEvent(Event):
    """Schema.org DanceEvent (subclass of Event)"""
    type: str = Field(default="DanceEvent")
    dance_style: Optional[List[str]] = Field(None, alias="danceStyle")
    
    # Dance-specific properties
    instructor: Optional[List[Union[str, Person]]] = None
    music_genre: Optional[List[str]] = Field(None, description="Music genres featured")
    difficulty_level: Optional[str] = Field(None, description="Beginner, Intermediate, Advanced")


class MusicEvent(Event):
    """Schema.org MusicEvent (subclass of Event)"""
    type: str = Field(default="MusicEvent")
    
    # Music-specific properties
    musical_genre: Optional[List[str]] = Field(None, description="Musical genres")
    musicians: Optional[List[Union[str, Person]]] = None


class EducationalEvent(Event):
    """Schema.org EducationalEvent (subclass of Event)"""
    type: str = Field(default="EducationalEvent")
    educational_level: Optional[str] = Field(None, alias="educationalLevel")
    teaches: Optional[List[str]] = None  # What skills/knowledge is taught
    
    # Educational properties
    course_mode: Optional[str] = Field(None, description="In-person, online, hybrid")
    certification_offered: Optional[str] = Field(None, description="Certification details")


class Course(SchemaOrgBase):
    """Schema.org Course"""
    type: str = Field(default="Course")
    provider: Optional[Union[str, Organization]] = None
    instructor: Optional[List[Union[str, Person]]] = None
    course_code: Optional[str] = Field(None, alias="courseCode")
    course_prerequisites: Optional[List[str]] = Field(None, alias="coursePrerequisites")
    educational_level: Optional[str] = Field(None, alias="educationalLevel")
    time_required: Optional[str] = Field(None, alias="timeRequired")  # Duration
    
    # Dance course specific
    dance_style: Optional[str] = Field(None, description="Primary dance style taught")
    skill_level: Optional[str] = Field(None, description="Target skill level")
    session_count: Optional[int] = Field(None, description="Number of sessions")


class CreativeWork(SchemaOrgBase):
    """Schema.org CreativeWork"""
    type: str = Field(default="CreativeWork")
    creator: Optional[Union[str, Person]] = None
    date_created: Optional[date] = Field(None, alias="dateCreated")
    date_published: Optional[date] = Field(None, alias="datePublished")
    license: Optional[str] = None
    copyright_holder: Optional[Union[str, Person, Organization]] = Field(None, alias="copyrightHolder")
    
    # Creative work properties
    medium: Optional[str] = None  # Photography, videography, choreography, etc.
    genre: Optional[List[str]] = None
    keywords: Optional[List[str]] = None


class VideoObject(CreativeWork):
    """Schema.org VideoObject (subclass of CreativeWork)"""
    type: str = Field(default="VideoObject")
    content_url: Optional[HttpUrl] = Field(None, alias="contentUrl")
    embed_url: Optional[HttpUrl] = Field(None, alias="embedUrl")
    duration: Optional[str] = None  # ISO 8601 duration
    video_quality: Optional[str] = Field(None, alias="videoQuality")


class Photograph(CreativeWork):
    """Schema.org Photograph (subclass of CreativeWork)"""
    type: str = Field(default="Photograph")
    content_url: Optional[HttpUrl] = Field(None, alias="contentUrl")
    
    # Photography specific
    camera_used: Optional[str] = Field(None, description="Camera equipment used")
    focal_length: Optional[str] = Field(None, description="Camera focal length")
    iso_speed: Optional[int] = Field(None, description="ISO setting")


# Database relationship models
class EventPersonRelation(BaseModel):
    """Relationship between Events and Persons"""
    event_id: str
    person_id: str
    role: str  # instructor, performer, organizer, attendee
    created_at: datetime = Field(default_factory=datetime.now)


class OrganizationPersonRelation(BaseModel):
    """Relationship between Organizations and Persons"""
    organization_id: str
    person_id: str
    role: str  # member, founder, instructor, volunteer
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    created_at: datetime = Field(default_factory=datetime.now)


class EventOrganizationRelation(BaseModel):
    """Relationship between Events and Organizations"""
    event_id: str
    organization_id: str
    relationship_type: str  # organizer, sponsor, partner, venue
    created_at: datetime = Field(default_factory=datetime.now)


# Graph database node labels for Neo4j
GRAPH_NODE_LABELS = {
    "Person": ["Person", "SchemaOrg"],
    "Organization": ["Organization", "SchemaOrg"],
    "DanceGroup": ["DanceGroup", "Organization", "SchemaOrg"],
    "Event": ["Event", "SchemaOrg"],
    "DanceEvent": ["DanceEvent", "Event", "SchemaOrg"],
    "MusicEvent": ["MusicEvent", "Event", "SchemaOrg"],
    "EducationalEvent": ["EducationalEvent", "Event", "SchemaOrg"],
    "Course": ["Course", "SchemaOrg"],
    "Place": ["Place", "SchemaOrg"],
    "CreativeWork": ["CreativeWork", "SchemaOrg"],
    "VideoObject": ["VideoObject", "CreativeWork", "SchemaOrg"],
    "Photograph": ["Photograph", "CreativeWork", "SchemaOrg"],
}

# Relationship types for graph database
GRAPH_RELATIONSHIPS = {
    "PERFORMS_AT": {"from": "Person", "to": "Event"},
    "INSTRUCTS": {"from": "Person", "to": "Event"},
    "ORGANIZES": {"from": "Organization", "to": "Event"},
    "LOCATED_AT": {"from": "Event", "to": "Place"},
    "MEMBER_OF": {"from": "Person", "to": "Organization"},
    "FOUNDED": {"from": "Person", "to": "Organization"},
    "TEACHES": {"from": "Person", "to": "Course"},
    "PROVIDES": {"from": "Organization", "to": "Course"},
    "CREATED": {"from": "Person", "to": "CreativeWork"},
    "FEATURES": {"from": "Event", "to": "CreativeWork"},
    "SPONSORS": {"from": "Organization", "to": "Event"},
    "PARTNERS_WITH": {"from": "Organization", "to": "Organization"},
    "KNOWS": {"from": "Person", "to": "Person"},
    "SPECIALIZES_IN": {"from": "Person", "to": "DanceStyle"},  # Custom node type
}
"""Centralized models — one `Base`/metadata (per CLAUDE.md), split across files by domain so no
single file grows unbounded. Every existing `from app.models import X` import keeps working
unchanged: this package re-exports every model from its submodule.

Add a new domain's models to their own file here (mirroring `app/features/<domain>/`), then
re-export it below — never let any one file creep back past the line-length soft target.
"""

from app.models.activities import Activity, ActivityParticipant
from app.models.admin import AdminAuditLog, AdminMembership
from app.models.campus import CampusPosition, CampusPost, CampusPostRead, CampusResource, VerificationRequest
from app.models.core import (
    Interest,
    Language,
    LookingForOption,
    Profile,
    User,
    UserLanguage,
    profile_interests,
    user_looking_for,
)
from app.models.employers import EmployerAccount, EmployerOrganization
from app.models.groups import Group
from app.models.messaging import Conversation, ConversationMember, Message
from app.models.notifications import DeviceToken, Notification
from app.models.programs import Program, ProgramMembership, ScholarProfessionalProfile
from app.models.social import Block, ConnectionRequest, Match, Report

__all__ = [
    'Activity',
    'ActivityParticipant',
    'AdminAuditLog',
    'AdminMembership',
    'Block',
    'CampusPosition',
    'CampusPost',
    'CampusPostRead',
    'CampusResource',
    'ConnectionRequest',
    'Conversation',
    'ConversationMember',
    'DeviceToken',
    'EmployerAccount',
    'EmployerOrganization',
    'Group',
    'Interest',
    'Language',
    'LookingForOption',
    'Match',
    'Message',
    'Notification',
    'Profile',
    'Program',
    'ProgramMembership',
    'Report',
    'ScholarProfessionalProfile',
    'User',
    'UserLanguage',
    'VerificationRequest',
    'profile_interests',
    'user_looking_for',
]

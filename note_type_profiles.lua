-- Note type profiles for the dictionary-only flashcard plugin.

local NoteTypeProfiles = {}

NoteTypeProfiles.DEFAULT_MODEL = "Vocabulary Card"

-- Dictionary-only vocabulary cards.
NoteTypeProfiles.VOCABULARY_CARD_MODEL = "Vocabulary Card"

-- Verbatim memorization (LPCG-style line cards).
NoteTypeProfiles.MEMORIZATION_MODEL = "Memorization"
NoteTypeProfiles.POETRY_MODEL = NoteTypeProfiles.MEMORIZATION_MODEL

local function norm(s)
    return (s or ""):lower():match("^%s*(.-)%s*$") or ""
end

function NoteTypeProfiles.normalize_model_name(name)
    if not name or name == "" then return NoteTypeProfiles.DEFAULT_MODEL end
    return name
end

function NoteTypeProfiles.is_vocabulary_card(model)
    return norm(model) == norm(NoteTypeProfiles.VOCABULARY_CARD_MODEL)
end

function NoteTypeProfiles.is_memorization(model)
    local n = norm(model)
    return n == norm(NoteTypeProfiles.MEMORIZATION_MODEL)
        or n == norm(NoteTypeProfiles.POETRY_MODEL)
end

function NoteTypeProfiles.is_basic(model)
    return norm(model) == "basic"
end

-- Vocabulary (dictionary) cards can target any note type except the
-- memorization type (which has its own LPCG-specific field layout). The
-- dictionary data is mapped onto the chosen type's fields by name heuristics.
function NoteTypeProfiles.is_vocabulary_compatible(model)
    if not model or model == "" then return false end
    if NoteTypeProfiles.is_memorization(model) then return false end
    return true
end

function NoteTypeProfiles.is_memorization_compatible(model)
    return NoteTypeProfiles.is_memorization(model)
end

function NoteTypeProfiles.profile_type(model)
    if NoteTypeProfiles.is_vocabulary_card(model) then return "vocabulary" end
    if NoteTypeProfiles.is_basic(model) then return "basic" end
    return "generic"
end

NoteTypeProfiles.VOCABULARY_CARD_FIELDS = {
    "Phrase", "Definition", "Etymology", "Context", "Source",
}

NoteTypeProfiles.MEMORIZATION_FIELDS = {
    "Title", "Context", "Target", "FullText", "Source", "LineIndex", "FullRecite",
}

function NoteTypeProfiles.vocabulary_field_set(field_names)
    if type(field_names) ~= "table" then return false end
    local need = {}
    for _, f in ipairs(NoteTypeProfiles.VOCABULARY_CARD_FIELDS) do need[f] = true end
    local count = 0
    for _, f in ipairs(field_names) do
        if need[f] then count = count + 1 end
    end
    return count >= 3
end

return NoteTypeProfiles


string HG_TypeToExpandedName(float t) {
	switch(t) {
		case HG_NORMAL:         return "Grenade";
		case HG_NAPALM:         return "Napalm Grenade";
		case HG_REMOTE:         return "Remote Mine";
        case HG_PLASMA:         return "Plasma Bomb";
        case HG_PLASMA_SHARD:   return "Plasma Bomb";
		default		  :         return "Fuckoff Grenade";
	}
}

string HG_TypeToName(float t) {
	switch(t) {
		case HG_NORMAL:         return "normal";
		case HG_NAPALM:         return "napalm";
		case HG_REMOTE:         return "remote";
        case HG_PLASMA:         return "plasma";
		default		  :         return "fuckoff";
	}
}

float HG_NameToType(string t) {
	switch(t) {
		case "napalm": return HG_NAPALM;
        case "remote": return HG_REMOTE;
        case "plasma": return HG_PLASMA;
		default		 : return HG_NORMAL;
	}
}

string HG_NameToExpandedName(string t) {
    return HG_TypeToExpandedName(HG_NameToType(t));
}
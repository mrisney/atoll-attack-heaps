package render;

/**
	The three weather patterns (owner: "we have essentially 3 weather
	patterns, fog, sunny and rain/stormy"). Purely visual for now: the sim
	doesn't know about weather. Each visual style starts in one (Ink map
	sunny, Painted rain, Sketch fog), and **C** cycles them (`?weather=`).
**/
enum Weather {
	Sunny;
	Fog;
	Rain;
}

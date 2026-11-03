package render;

/**
	The three weather patterns (owner: "we have essentially 3 weather
	patterns, fog, sunny and rain/stormy"). Purely visual for now: the sim
	doesn't know about weather. Ink map starts sunny, Painted rainy, and
	Sketch with none (owner: leave the drawing as it was); **C** cycles them
	(`?weather=`).
**/
enum Weather {
	Sunny;
	Fog;
	Rain;
}

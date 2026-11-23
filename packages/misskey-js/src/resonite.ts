export type ResoniteTextPart = { text: string; color?: string };

export type ResonitePreview = {
	type: 'world' | 'session';
	state: 'available' | 'unavailable' | 'ended' | 'error';
	titleParts?: ResoniteTextPart[];
	creator?: string;
	worldUrl?: string;
	visits?: number;
	currentUsers?: number;
	maxUsers?: number;
	createdAt?: string;
	updatedAt?: string;
	featured?: boolean;
};

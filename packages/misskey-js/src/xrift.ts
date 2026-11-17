/** Metadata attached to an XRift URL preview by the server. */
export type XriftPreview = {
	type: 'world' | 'instance' | 'user';
	state: 'available' | 'unavailable' | 'error';
	creator: string | null;
	worldUrl?: string;
	totalVisits?: number;
	visitsLast7Days?: number;
	publicInstances?: number;
	createdAt?: string;
	totalWorlds?: number;
	worlds?: { url: string; title: string; thumbnail: string | null }[];
};

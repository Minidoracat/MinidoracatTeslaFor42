#version 330

// MinidoracatTesla_viewpoint (the cabin detail model, part CabinDetail): only Project Viewpoint draws it, with its own
// shaders and the model's texture (a part model whose shader is not a vehicle shader, viewpoint/models/VehicleCapture);
// here every vertex goes past the far plane, so the game's own view of the car (isometric) draws nothing more.

layout (location = 0) in vec4 vertex;

void main()
{
	gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
}

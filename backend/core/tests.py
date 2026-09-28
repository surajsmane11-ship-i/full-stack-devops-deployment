from django.test import TestCase, Client


class HelloWorldTestCase(TestCase):
    def setUp(self):
        self.client = Client()

    def test_hello_world_status_code(self):
        """Test that /api/hello/ returns HTTP 200"""
        response = self.client.get('/api/hello/')
        self.assertEqual(response.status_code, 200)

    def test_hello_world_response_content(self):
        """Test that the response contains the expected message"""
        response = self.client.get('/api/hello/')
        data = response.json()
        self.assertIn('message', data)
        self.assertEqual(data['message'], 'Hello World from Django Backend!')
